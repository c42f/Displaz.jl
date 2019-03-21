# Displaz

Bindings for the [displaz lidar viewer](https://github.com/c42f/displaz) for
flexible three dimensional plotting of large point clouds, lines and meshes.

## Installation

Check the [installation instructions](https://github.com/c42f/displaz#installation) at displaz's repository.
Then install `Displaz.jl` using the REPL `Pkg` mode:
```julia
(v1.0) pkg> add Displaz
```

## Quickstart

To plot a point cloud of 10⁵ points, where every point position is a column in a
matrix:

```julia
using Displaz

plot3d!(10*randn(3,100000))
```


To plot a point cloud of 10⁶ points with random orange and red HSV colors:

```julia
using Displaz
using Colors

N = 1000_000
position = 10*randn(3,N)
color = [HSV(80*rand(), 0.8, 1) for i=1:N]
plot3d!(position, color=color, label="Example2")
```


To plot a set of 5 vertices, and line series between a subset of these vertices:

```julia
using Displaz
using Colors
using StaticArrays

# Clear plots
clearplot()

N = 5
# Random points
position = rand(SVector{3,Float64}, N)
# Plot points
plot3d!(position, color=[Gray{Float64}(i/N) for i=1:N], label="Example3 Points")
# Plot a pair of line series between vertices 1:2 and 3:5
plot3d!(position, color="r", linebreak=[1,3], markershape="-", label="Example3 Lines")
# mutate the color of the first two points (efficient for modifying a subset of points)
Displaz.mutate!("Example3 Points", 1:2; color = [Gray{Float64}(1.0)])
```
