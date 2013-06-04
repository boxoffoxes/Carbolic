PASSES=


#a.out : optimised.ll
#	clang -o $@ $<

optimised.ll : unoptimised.ll
	opt -S -o $@ $(PASSES) $<

clean :
	rm -rf */
