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

type mode = Random | TreeSample | HillClimb | MCTS

let shuffle_list l =
    let srt _ _ = ( Random.int 10 <= Random.int 10 ) in
    List.sort srt l
;;


module MCTS = struct
    type node = {
        untried : string list ;
        children : node list ;
        static_opts : string list ;
        visits : int ;
        wins : int ;
        perf : float ;
    } ;;

    let ucb1 parent node = 
        (* UCB1 algorithm *)
        node.wins /. node.visits
            +. sqrt( 2.0 *. log(parent.visits) /.  node.visits )
    ;;

    let new_node () =
        let unvisited = shuffle_list optlib in
        { untried = unvisited ; children = [] ; static_opts = [] ; visits = 0 ; wins = 0 ; perf = 0.0 }
    ;;

    let select_child node =
        let ucb = ucb1 node in
        let srt n1 n2 = (ucb n1 > ucb n2) in
        let sorted_children = List.sort srt node.children
        List.head sorted_children ;;
    ;;

    let rec uct node depth =
        
    ;;
end





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

let rec benchmark_n_times cmd n =
    match n with 
    | 0 -> 
        let tm = Unix.times () in
        let time = (tm.Unix.tms_cstime +. tm.Unix.tms_cutime ) in
        time
    | _ -> 
        match run_child_process cmd with
        | true -> 
            benchmark_n_times cmd (n-1) 
        | false -> 
            exit 0 ; 
;;

let benchmark binary =
    let a = fork () in
    match a with
    | 0 -> (
        let path = Sys.getcwd () in
        let cmd = [| String.concat "/" [path ; binary] |] in
        let n = 3 in
        let tm = ( benchmark_n_times cmd n ) /. (float_of_int n) in
        let fh = open_out_gen [Open_append ; Open_creat] 0o644 "perf.txt" in
        output_string fh (string_of_float tm) ;
        output_string fh "\n" ;
        close_out fh ;
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
    String.concat "/" ( "./" :: List.map strip_leading_dash (List.rev opts) )
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

let rec new_static_opts results static_opts =
        let best = pick_best results in
        let static_opts' = best :: static_opts in
        let candidate_res =  compile_and_benchmark (dir_of_opts static_opts') static_opts' in
        match candidate_res with (* check the candidate actually runs! *)
        | None -> new_static_opts (List.tl results) static_opts
        | _ -> static_opts'
;;

let rec compilation_cycle optlib depth static_opts = match depth with 
    | 0 -> exit 0; 
    | _ -> 
        let simulate opt = run_simulations [] depth 50 (opt :: static_opts) in
        let results = List.map simulate optlib in
        let static_opts' = new_static_opts results static_opts in
        compilation_cycle optlib (depth-1) static_opts'
;;

let random_compilation_cycle depth n = match n with 
    | 0 -> exit 0;
    | _ ->
            run_simulations [] depth n [] ;
;;

let rec dumb_hillclimb_compilation_cycle depth static_opts = match depth with
    | 0 -> exit 0 ;
    | _ -> 
        let simulate opt = run_simulations [] 0 1 (opt :: static_opts) in
        let results = List.map simulate optlib in
        let static_opts' = new_static_opts results static_opts in
        dumb_hillclimb_compilation_cycle (depth-1) static_opts'
;;

(* let rec hill_climbing_compilation_cycle  = 
;; *)

let usage () =
    List.iter print_string [
        "Usage: " ; Sys.argv.(0) ; " [args]\n" ;
        "Where [args] can be: \n" ;
        "\t--random      Use random search" ;
        "Default search strategy is tree descent with sampling" ;
    ] ;
    exit 0;
;;

let rec parse_args args = match args with
    | []               -> TreeSample
    | "--random" :: [] -> Random
    | "--hill" :: []   -> HillClimb
    | "--mcts" :: []   -> MCTS
    | _                -> usage () ;
;;

let main () = 
    Random.self_init () ;
    let mode = parse_args ( List.tl ( Array.to_list Sys.argv)) in
    match mode with
        | TreeSample ->
            let _ = compilation_cycle optlib 10 [] in
            exit 0 ;
        | Random -> 
            let _ = random_compilation_cycle 10 23500 in
            exit 0 ;
        | HillClimb ->
            let _ = dumb_hillclimb_compilation_cycle 10 [] in
            exit 0 ;
        | _ -> usage () ;
;;

main () ;
