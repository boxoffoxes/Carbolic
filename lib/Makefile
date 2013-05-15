
% : %.O1 %.O2 %.O3
	echo Done


%.x1 : %.llvm
	opt --print-after-all -S -o $@ -adce -basiccg -deadargelim $<

%.x2 : %.llvm
	opt --print-after-all -S -o $@ -gvn -indvars -die -adce $<

%.O1 : %.llvm
	opt --print-after-all -S -O1 $< -o $@

%.O2 : %.llvm
	opt --print-after-all -S -O2 $< -o $@

%.O3 : %.llvm
	opt --print-after-all -S -O3 $< -o $@


%.llvm : %.c
	clang $< -S -emit-llvm -o $@
