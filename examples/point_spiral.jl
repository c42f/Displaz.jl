using Displaz

function example(N)
    t = range(0, stop=1, length=N)'
    P = (10 .+ 0.2*rand(Float64, size(t))) .* vcat(exp.(5*t).*cos.(100*pi*t),
                                                   exp.(5*t).*sin.(100*pi*t),
                                                   100*t);
    C = vcat(t, 1 .- t, zero(t));
    sz  = map(Float32, t)
    shape = mod.(rand(UInt8, N), 6)
    plot3d!(P, color = C, label="Top series", markershape=shape)
    P[3,:] = -P[3,:]
    plot3d!(P, color = C, markersize = sz, markershape="-", label="Bottom series")
end

example(1_000_000)

