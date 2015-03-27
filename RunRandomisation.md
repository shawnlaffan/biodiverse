


# Introduction #

This is documentation for the run\_randomisation utility that comes with Biodiverse version 0.18\_007 and later.

The purpose of this utility is to run randomisations external to the GUI, meaning an analysis can be set up to run as a background task without the GUI and its feedback windows.

# Usage and arguments #

If using the executable version then either of 64 or 32 bit versions can be run (depending on your system):
```
run_randomisation_x64.exe --basedata <basedata file> --rand_name <randomisation name> --iterations <default is 10> --args arg1=some_val arg2=some_val
run_randomisation_x32.exe --basedata <basedata file> --rand_name <randomisation name> --iterations <default is 10> --args arg1=some_val arg2=some_val
```

If using the perl script (source code install):
```
perl run_randomisation.pl --basedata <basedata file> --rand_name <randomisation name> --iterations <default is 10> --args arg1=some_val arg2=some_val
```

For example:
```
run_randomisation_x64.exe --basedata Example.bds --rand_name rand_test --iterations 10 --args function=rand_csr_by_group seed=12768545 max_iters=999 save_checkpoint=99
```

Note that there should be no spaces between the argument name, equals sign and value.  Use quotes if an argument has any special characters or whitespace (e.g. to use the name `rand structa` then put it in quotes: `"rand structa"`).

To see the help at the command line, specify --help or --h as an argument.  Note that this help also lists which arguments can be abbreviated.
```
run_randomisation_x64.exe --help
run_randomisation_x32.exe --help
perl run_randomisation.pl --help
```

```
run_randomisation.pl
--basedata  --bd Basedata file name
--rand_name  --r Randomisation output name
--iterations --i Number of randomisation iterations [default is 10]
--args           Rest of randomisation args as
                 key=value pairs,
                 with pairs separated by spaces

--help       Print this usage and exit
```

The "rest of the randomisation args" list is all the other arguments for the randomisation, and will vary depending on what is being used.  Examples include `seed` for the PRNG starting seed, `richness_multiplier` and `richness_addition` for the rand\_structured analysis, and `save_checkpoint` to periodically save copies of the basedata file if such are needed.


# When is this useful? #

This utility is probably most useful when you have a large data set and the randomisations take a long time.  Using this utility, you can divide the task into multiple sub-randomisations and then recombine the results once they are completed (currently this needs to be done outside of Biodiverse, e.g. in R once the results have been exported).  If you have access to a High Performance Computer cluster then you could potentially run 100 iterations on each of 50 cores to more quickly generate 5000 randomisation iterations.  But why stop there when you can do 50 on each of 100 cores?  Or more if they let you?

# Caveats and gotchas #

  * Any arguments to control the randomisation results that are changed between runs will be ignored (e.g. `richness_addition` and `seed`).  Any new PRNG seeds specified after any iterations have been run will also be ignored, and the system will start from the PRNG state at the end of the last completed iteration.  This is the same behaviour as the GUI except that the GUI disables access to the widgets to stop any changes being made.
  * If you use this utility to run multiple randomisations in parallel then make sure you create a new randomisation output for each parallel run, as the randomisations are incremental across runs and iterations so that the randomisation will restart from the last iteration that was saved.  If your separate runs all use the same existing object then they will all be the same, even if you pass a new seed argument (any new arguments are ignored after the first iteration - see previous point).
  * The incremental approach also means that, if you run 10 iterations of a randomisation in one process and then run a second set of 10, the result will be identical to running all 20 iterations in one process.
  * If a basedata is loaded into a GUI project and additional randomisation iterations are run under the GUI then these will not be saved into the basedata file when the project is saved.  If you want to maintain analytical continuity then the basedata must be deliberately saved from the GUI, overwriting if necessary by using the same file name (or to a new filename to be safe).

# Ignoring new arguments is useful #

A useful side-effect of the argument handling is that one does not need to specify all the control arguments for an existing randomisation.  Just specify the basedata, the randomisation name and iterations (if non-default values are needed).  For example the following commands are equivalent if Example.bds already contains a randomisation output called rand\_test.
```
run_randomisation_x64.exe --basedata Example.bds --rand_name rand_test --iterations 99 --args function=rand_csr_by_group seed=12768545 max_iters=999 save_checkpoint=99
run_randomisation_x64.exe --basedata Example.bds --rand_name rand_test --iterations 99
```

# Limitations #

You need to be able to store all of the following within your system memory limits at the same time:  1) the BaseData file including all of its outputs, 2) the randomised BaseData, and 3) the random comparator of the largest of the BaseData analyses.  The `rand_structured` randomisation also requires an additional copy of the BaseData for control purposes.  If you cannot store these within memory then the system will not be able to complete even a single iteration and the randomisations cannot be completed.

If you cannot access a machine with bigger memory limits then the workarounds involve reducing the memory requirements using divide and conquer approaches.  These can be used in tandem, and complex analyses are best done using a scripting approach to avoid human error (after debugging of course).

  1. Reduce the number of indices being assessed in each analysis output.  The system only keeps one randomised output result in memory at a time so you might be able to squeeze below the limits this way.
  1. Subdivide the moving window analyses spatially using a set of definition queries.  _Note that this is not appropriate for most cluster analyses as definition queries exclude groups from clustering_ (but maybe that's what you want, and who are we to argue?).  For the moving window analyses, try dividing them into halves first, then quarters, etc.  An example using the western and eastern halves with two definition queries is:  `$x < 200000` and `$x >= 200000` (the `>=` in the second is needed to ensure all groups are considered).  Each subdivision should have the same calculations specified.  Any exported results can be recombined externally to Biodiverse to make a single result file (e.g. in a database or GIS program).
  1. Duplicate the BaseData file and store subsets of the outputs in each new BaseData file.  Then re-run the randomisations as many times as there are new BaseDatas, but making sure you specify the same starting seed for each.  The seed ensures the randomised BaseDatas will all be identical (replicated) at each iteration, and the end result is the same as doing them all within the one BaseData (if it would fit within memory).  This can take much longer than the other options as each randomisation iteration must be regenerated for each replicated BaseData.  Randomisations of large data sets using the rand\_structured function will take the longest, as the system must reconverge on the richness targets for each replicated iteration (it does not record how it did it, but the seed ensures the same result each time).