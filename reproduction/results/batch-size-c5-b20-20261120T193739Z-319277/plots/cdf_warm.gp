load "../../../style.gpi"
# Override with Tol bright palette
set style line 1 linecolor rgb "#4477AA"
set style line 2 linecolor rgb "#EE6677"
set style line 3 linecolor rgb "#228833"
set style line 4 linecolor rgb "#CCBB44"
set style line 5 linecolor rgb "#AA3377"
set output "cdf_warm.eps"
set xlabel "Latency (ms)"
set ylabel "CDF"
set xrange [0:60]
set yrange [0:1]
set key bottom right

plot "codoh-full_warm.cdf" using 1:2 with lines ls 5 dt 5 lw 3 title "CODoH"
