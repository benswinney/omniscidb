select
  x100k,
  y10,
  count(z10),
  sum(z10),
  max(z10),
  min(z10),
  avg(z10)
from
  ##TAB##
group by 
    x100k,
    y10
limit 1000