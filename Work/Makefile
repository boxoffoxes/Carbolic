PASSES=


a.out : countdown.hs
	ghc -O0 -o $@ -fllvm -fforce-recomp $(PASSES) $<

#a.out : optimised.ll
#	clang -o $@ $<

optimised.ll : unoptimised.ll
	opt -S -o $@ $(PASSES) $<

clean :
	rm -rf */
