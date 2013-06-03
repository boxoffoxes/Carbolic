open Unix


(*
 * Compile and benchmark unoptimised case
 * Create dir named after each possible optimisation
 * 
 *)

let optlib = [ "-adce" ; "-basicaa" ; "-basiccg" ; "-constmerge" ;
    "-correlated-propagation" ; "-deadargelim" ; "-domtree" ; 
    "-dse" ; "-early-cse" ; "-functionattrs" ; "-globalopt" ; 
    "-gvn" ; "-indvars" ; "-inline" ; "-instcombine" ; "-ipsccp" ; 
    "-jump-threading" ; "-lazy-value-info" ; "-lcssa" ; "-licm" ; 
    "-loop-deletion" ; "-loop-idiom" ; "-loop-rotate" ; 
    "-loop-simplify" ; "-loop-unroll" ; "-loop-unswitch" ; 
    "-loops" ; "-lower-expect" ; "-memcpyopt" ; "-memdep" ; 
    "-no-aa" ; "-preverify" ; "-prune-eh" ; "-reassociate" ;
    "-scalar-evolution" ; "-scalarrepl" ; "-scalarrepl-ssa" ; 
    "-sccp" ; "-simplify-libcalls" ; "-simplifycfg" ; 
    "-strip-dead-prototypes" ; "-tailcallelim" ; "-targetlibinfo" ; 
    "-tbaa" ; "-verify" ]

let run_child_process args =
    (* Get the name of the executable from the first arg *)
    let cmd = args.(0) in
    let pid = fork () in
    match pid with
    | 0 -> Unix.execv cmd args ;
    | -1 -> raise ( Failure "Failed to run program!" )
    | _ -> ignore ( wait () ) ;
;;

let prepare dir = 
    Unix.mkdir dir 0o755 ;
    Unix.symlink "../Makefile" dir ;
    Unix.symlink "../unoptimised.ll" dir ;
;;

let compile opts =
    let optstr = String.concat " " opts in
    let cmd = String.concat "" [ "make " ; "PASSES=\"" ; optstr ; "\"" ] in
    ignore ( Sys.command cmd ) ;
    "a.out"
;;

let random_opt optlib =
    let sz = Array.length optlib in
    let i = Random.int sz in
    optlib.(i)
;;

let rec k_random_opts k =
    let ol = Array.of_list optlib in
    let ropts = Array.make k "" in
    for i=0 to k-1 do
        ropts.(i) <- random_opt ol
    done ;
    Array.to_list ropts
;;


let benchmark binary =
    let a = fork () in
    match a with
    | 0 -> (
        let path = Sys.getcwd () in
        let cmd = [| String.concat "/" [path ; binary] |] in
        run_child_process cmd ;
        let tm = Unix.times () in
        print_float (tm.Unix.tms_cstime +. tm.Unix.tms_cutime ) ;
        exit 0 ;
        (* TODO: this won't work! Doesn't return value to parent! *)
    )
    | -1 -> raise ( Failure "Failed to fork a child process" )
    | _  -> ignore ( wait () ) ;
;;

let compile_and_benchmark dir opts =
    let olddir = Sys.getcwd () in
    prepare dir ;
    Sys.chdir dir ;
    let binary = compile opts in
    let score = benchmark binary in
    Sys.chdir olddir ;
    score
;;

let dir_of_opts opts = 
    let strip_leading_dash str = String.sub str 1 (String.length str - 1) in
    String.concat "/" ( List.map strip_leading_dash opts )
;;
let hash lst = 
    Digest.to_hex ( Digest.string ( String.concat " " lst ) )
;;

let rec run_simulations results k n static_opts = match n with
    | 0 -> ()
    | _ ->
        let ropts = k_random_opts k in
        let wd = dir_of_opts static_opts in
        let subdir = String.concat "/" [ wd ; hash ropts ] in
        let result = compile_and_benchmark subdir (List.concat [ropts ; static_opts]) in

        run_simulations ( result :: results ) k (n-1) static_opts 
;;

let pick_best = List.hd ;;

let rec compilation_cycle optlib static_opts =
    let results = List.map ( run_simulations [] 10 10 ) optlib in
    let best = pick_best results in
    exit 0 ;
    compilation_cycle optlib (best :: static_opts)
;;


let main () = 
    compilation_cycle optlib []
;;
