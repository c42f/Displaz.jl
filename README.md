# Displaz

Bindings for the [displaz lidar viewer](https://github.com/c42f/displaz) -
flexible three dimensional plotting of large point clouds.  Also supports line
segments and meshes.  A minimal example:

```julia
using Displaz

plot3d(100*randn(3,100000))
```
