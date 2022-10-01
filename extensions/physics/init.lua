local p = { }

local root = (...)

p.newCylinder = require(root .. "/shapes/cylinder")
p.newMesh = require(root .. "/shapes/mesh")
p.newObject = require(root .. "/shapes/object")

p.newWorld = require(root .. "/world")
p.newCollider = require(root .. "/collider")

return p