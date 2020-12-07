library (picante)


source ("ind_swaps.r")

# you will need to unzip this file
acacia = read.csv ("acacia_sites_by_spp.csv", row.names=1)
acacia = acacia[,c(-1,-2)]

aa = as.matrix(acacia)
aa[is.na(aa)] = 0



indswaps = function (mx, intervals, maxattempts) {
  m = as.matrix(mx)
  
  row_nums = 1:nrow(m)
  nrows = nrow(m)
  col_nums = 1:ncol(m)
  ncols = ncol(m)
  attempts = 0
  nonzero  = sum (m > 0)
  if (missing(maxattempts)) {
    maxattempts = 200 * nonzero
  }
  
  for(swap in 1:intervals) {
    
    while(1) {
      attempts = attempts+1
      if (attempts > maxattempts) {
        message ("max attempts reached ", attempts)
        message ("total swaps ", swap)
        return (m)
      }
      # Choose random rows without replacement
      rows = sample.int(nrows, 2, replace=FALSE, useHash = TRUE)
      i = rows[1]
      j = rows[2]
      # Choose random cols without replacement
      cols = sample.int(ncols, 2, replace=FALSE, useHash = TRUE)
      k = cols[1]
      l = cols[2]
      # message (paste (i, j, k, l))
      # message (m[i,k])
      if(   (m[i,k]>0.0 && m[j,l]>0.0 && (m[i,l]+m[j,k])==0.0) 
            || ((m[i,k]+m[j,l])==0.0 && m[i,l]>0.0 && m[j,k]>0.0))
      {
        # currently swaps abundances within columns (=species)
        # should have a switch to swap abundances within rows, columns, or random
        tmp = m[i,k];
        m[i,k] = m[j,k];
        m[j,k] = tmp;
        tmp = m[i,l];
        m[i,l] = m[j,l];
        m[j,l] = tmp;
        # swapped = 1;
        break;
      }
    }
  }
  message ("Attempts: ", attempts)
  m
} 





for (i in (c(#150,
             14754,
             58350
             # 20000
             # 29000, 
             # 50000
             # 100000, 
             # 200000, 
             # 24610589,
             # 97949240
             ))) {
  message ("Running ", i, " iterations")
  flush.console()
  
  #t = Sys.time()
  t = system.time({
    aar = randomizeMatrix(aa, null.model="independentswap", iterations = i)
  })
  message (paste (t, " "))
  #message (paste (Sys.time()-t))
  #flush.console()
  
  #t = Sys.time()
  t = system.time({
    aar2 = indswaps (aa, i, 2^31-1)
  })
  message (paste (t, " "))
  #message (paste (Sys.time()-t))
  #flush.console()
}

