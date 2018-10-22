--[[
	Renderer that deals in terms of Roblox Instances. This is the most
	well-supported renderer after NoopRenderer and is currently the only
	renderer that does anything.
]]

local Binding = require(script.Parent.Binding)
local Children = require(script.Parent.PropMarkers.Children)
local ElementKind = require(script.Parent.ElementKind)
local Ref = require(script.Parent.PropMarkers.Ref)
local Type = require(script.Parent.Type)
local getDefaultPropertyValue = require(script.Parent.getDefaultPropertyValue)

local function applyRef(ref, newRbx)
	if ref == nil then
		return
	end

	if type(ref) == "function" then
		ref(newRbx)
	elseif Type.of(ref) == Type.Binding then
		Binding.update(ref, newRbx)
	else
		error(("Invalid ref: Expected type Binding but got %s"):format(
			typeof(ref)
		))
	end
end

local function setHostProperty(node, key, newValue, oldValue)
	if newValue == oldValue then
		return
	end

	if typeof(key) == "string" then
		if newValue == nil then
			local hostClass = node.hostObject.ClassName
			local _, defaultValue = getDefaultPropertyValue(hostClass, key)
			newValue = defaultValue
		end

		-- Assign the new value to the object
		node.hostObject[key] = newValue

		return
	end

	if key == Children or key == Ref then
		-- Children and refs are handled elsewhere in the renderer
		return
	end

	local internalKeyType = Type.of(key)

	if internalKeyType == Type.HostEvent or internalKeyType == Type.HostChangeEvent then
		-- Event connections are handled in a separate pass
		return
	end

	-- TODO: Better error message
	error(("Unknown prop %q"):format(tostring(key)))
end

local function bindHostProperty(node, key, newBinding)

	local function updateBoundProperty(newValue)
		setHostProperty(node, key, newValue, nil)
	end

	if node.bindings == nil then
		node.bindings = {}
	end

	node.bindings[key] = Binding.subscribe(newBinding, updateBoundProperty)

	setHostProperty(node, key, newBinding:getValue(), nil)
end

local RobloxRenderer = {}

function RobloxRenderer.mountHostNode(reconciler, node)
	local element = node.currentElement
	local hostParent = node.hostParent
	local key = node.key

	assert(ElementKind.of(element) == ElementKind.Host)

	-- TODO: Better error messages
	assert(element.props.Name == nil)
	assert(element.props.Parent == nil)

	local instance = Instance.new(element.component)
	node.hostObject = instance

	for propKey, value in pairs(element.props) do
		if Type.of(value) == Type.Binding then
			bindHostProperty(node, propKey, value)
		else
			setHostProperty(node, propKey, value, nil)
		end
	end

	instance.Name = key

	local children = element.props[Children]

	if children ~= nil then
		for childKey, childElement in pairs(children) do
			local childNode = reconciler.mountVirtualNode(childElement, instance, childKey)

			node.children[childKey] = childNode
		end
	end

	instance.Parent = hostParent
	node.hostObject = instance

	applyRef(element.props[Ref], instance)
end

function RobloxRenderer.unmountHostNode(reconciler, node)
	local element = node.currentElement

	applyRef(element.props[Ref], nil)

	for _, childNode in pairs(node.children) do
		reconciler.unmountVirtualNode(childNode)
	end

	if node.bindings ~= nil then
		for _, disconnect in pairs(node.bindings) do
			disconnect()
		end
	end

	node.hostObject:Destroy()
end

function RobloxRenderer.updateHostNode(reconciler, node, newElement)
	local oldProps = node.currentElement.props
	local newProps = newElement.props

	-- If refs changed, detach the old ref and attach the new one
	if oldProps[Ref] ~= newProps[Ref] then
		applyRef(oldProps[Ref], nil)
		applyRef(newProps[Ref], node.hostObject)
	end

	-- Apply props that were added or updated
	for propKey, newValue in pairs(newProps) do
		local oldValue = oldProps[propKey]

		if newValue ~= oldValue then
			if Type.of(oldValue) == Type.Binding then
				local disconnect = node.bindings[propKey]
				disconnect()
				node.bindings[propKey] = nil
			end

			if Type.of(newValue) == Type.Binding then
				bindHostProperty(node, propKey, newValue)
			else
				setHostProperty(node, propKey, newValue, oldValue)
			end
		end
	end

	-- Apply props that were removed
	for propKey, oldValue in pairs(oldProps) do
		local newValue = newProps[propKey]

		if newValue == nil then
			if Type.of(oldValue) == Type.Binding then
				local disconnect = node.bindings[propKey]
				disconnect()
				node.bindings[propKey] = nil
			end

			setHostProperty(node, propKey, nil, oldValue)
		end
	end

	reconciler.updateVirtualNodeChildren(node, newElement.props[Children])

	return node
end

return RobloxRenderer
