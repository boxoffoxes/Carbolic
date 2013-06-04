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
;;

let cksums = Hashtbl.create 1000

let report_pid () =
    print_int ( Unix.getpid () ) ;
    print_newline () ;
;;

let run_child_process args =
    (* Get the name of the executable from the first arg *)
    let cmd = args.(0) in
    let pid = fork () in
    match pid with
    | 0 -> Unix.execv cmd args
    | -1 -> raise ( Failure "Failed to run program!" )
    | _ -> 
            let (pid, status) = Unix.wait () in
            match status with
            | WEXITED 0 -> true
            | _ -> false
;;

let prepare dir = 
    try 
       Unix.mkdir dir 0o755 ;
        Unix.symlink "../Makefile" (String.concat "/" [dir ; "Makefile"] ) ;
        Unix.symlink "../countdown.hs" (String.concat "/" [dir ; "countdown.hs"] ) ;
        (*Unix.symlink "../unoptimised.ll" (String.concat "/" [dir ; "unoptimised.ll"] ) ;*)
    with 
    | Unix.Unix_error ( EEXIST, "mkdir", _ ) -> () ;
;;

let compile opts =
    let optstr = String.concat " -optlo" (List.rev opts) in
    let cmd = String.concat "" [ "make " ; "PASSES=\"-optlo" ; optstr ; "\"" ] in
    let logfile = open_out "carbolic.log" in
    output_string logfile optstr ;
    output_string logfile "\n" ;
    ignore ( Unix.system cmd ) ;
    close_out logfile ;
    try
        Hashtbl.add cksums ( Digest.to_hex (Digest.file "a.out") ) true ;
        "a.out"
    with _ -> ""
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

let read_performance file =
    try
        let fh = open_in file in
        let score = float_of_string ( input_line fh ) in
        close_in fh ;
        Some score
    with
    | _ -> None

;;

let benchmark binary =
    let a = fork () in
    match a with
    | 0 -> (
        let path = Sys.getcwd () in
        let cmd = [| String.concat "/" [path ; binary] |] in
        match run_child_process cmd with
        | true ->
            let tm = Unix.times () in
            let fh = open_out_gen [Open_append ; Open_creat] 0o644 "perf.txt" in
            output_string fh (string_of_float (tm.Unix.tms_cstime +. tm.Unix.tms_cutime )) ;
            output_string fh "\n" ;
            close_out fh ;
            exit 0 ; 
        | false -> 
            exit 0 ; 
    )
    | -1 -> raise ( Failure "Failed to fork a child process" )
    | _  -> ignore ( wait () ) ;
;;

let compile_and_benchmark dir opts =
    let olddir = Sys.getcwd () in
    prepare dir ;
    Sys.chdir dir ;
    let binary = compile opts in
    benchmark binary ;
    let score = read_performance "perf.txt" in
    Sys.chdir olddir ;
    score
;;

let dir_of_opts opts = 
    let strip_leading_dash str = String.sub str 1 (String.length str - 1) in
    String.concat "/" ( List.map strip_leading_dash (List.rev opts) )
;;

let hash lst = 
    String.concat "" [ "00_" ; Digest.to_hex ( Digest.string ( String.concat " " lst ) ) ]
;;

let aggregate results =
    let filt v = match v with None -> false | _ -> true in
    let extract (Some f) = f in
    let vals =  List.map extract (List.filter filt results) in
    let sum = List.fold_left (+.) 0.0 vals in
    sum /. (float_of_int (List.length vals))
;;
    

let rec run_simulations results k n static_opts = match n with
    | 0 -> ( List.hd static_opts, aggregate results )
    | _ ->
        let ropts = k_random_opts k in
        let wd = dir_of_opts static_opts in
        prepare wd ;
        let subdir = String.concat "/" [ wd ; hash ropts ] in
        let result = compile_and_benchmark subdir (List.concat [ropts ; static_opts]) in

        run_simulations ( result :: results ) k (n-1) static_opts 
;;

let pick_best results =
    let cmp (_, f1) (_, f2) = compare f1 f2 in
    let rs = List.sort cmp results in
    let ignore_zero (_, f) = (f != 0.0) in
    fst ( List.hd ( List.filter ignore_zero rs ) )
;;

let rec compilation_cycle optlib depth static_opts = match depth with 
    | 0 -> exit 0; 
    | _ -> 
        let simulate opt = run_simulations [] depth 50 (opt :: static_opts) in
        let results = List.map simulate optlib in
        let best = pick_best results in
        let static_opts' = best :: static_opts in
        ignore ( compile_and_benchmark (dir_of_opts static_opts') static_opts' ) ;
        compilation_cycle optlib (depth-1) static_opts'
;;


let main () = 
    Random.self_init () ;
    let _ = compilation_cycle optlib 10 [] in
    exit 0 ;
;;

main () ;
