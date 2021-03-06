open Unix
open Printf

(*
 * Compile and benchmark unoptimised case
 * Create dir named after each possible optimisation
 * 
 *)

(* Todo: feature requests
 *
 *  - Optimisation library loading
 *  - commandline option for specifying optimisation library
 *  - Separate benchmarks and data files (to avoid 
 *  - Better logging
 *  - commandline options for depth
 *  - alternative models to fixed-depth optimisation
 *  - functorise search strategies
 *  - split source file
 *  - modularise compiler support
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
type settings = {
    mutable max_depth : int ;
    mutable max_iter  : int ;
    mutable mode      : mode ;
    mutable debug     : bool ;
    mutable opt       : string ;
    mutable filename  : string ;
}

exception NoResults

let settings = {
    max_depth = 10 ;
    max_iter  = 2000 ;
    mode = TreeSample ;
    debug = false ;
    opt = "-O0" ;
    filename = "" ;
}

let fail format =
    ksprintf failwith format
;;

let shuffle_list l =
    let srt _ _ = compare (Random.int 10) (Random.int 10) in
    List.sort srt l
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
    | -1 -> failwith "Failed to run program!" 
    | _ -> 
            let (pid, status) = Unix.wait () in
            match status with
            | WEXITED 0 -> true
            | _ -> false
;;

let prepare dir = 
    let linktarget = "../" ^ settings.filename in
    try 
       Unix.mkdir dir 0o755 ;
        Unix.symlink "../Makefile" (String.concat "/" [dir ; "Makefile"] ) ;
        Unix.symlink linktarget (String.concat "/" [dir ; settings.filename] ) ;
        (*Unix.symlink "../unoptimised.ll" (String.concat "/" [dir ; "unoptimised.ll"] ) ;*)
    with 
    | Unix.Unix_error ( EEXIST, "mkdir", _ ) -> () ;
;;

let compile opts =
    let optstr = String.concat " -optlo" (List.rev opts) in
    (* let cmd = String.concat "" [ "ghc " ; settings.opt ; " -o a.out -fllvm -fforce-recomp -optlo" ; optstr ; " " ; settings.filename ] in *)
    let cmd = String.concat "" [ "make " ; "PASSES=\"" ; optstr ; "\"" ] in
    let logfile = open_out "carbolic.log" in
    print_endline cmd ;
    output_string logfile cmd ;
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
    | -1 -> failwith "Failed to fork a child process" 
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
    let num = List.length vals in
    match num with
    | 0 -> raise NoResults
    | _ -> sum /. (float_of_int num)
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
    | 0 -> (); 
    | _ -> 
        let simulate opt = run_simulations [] depth 50 (opt :: static_opts) in
        let results = List.map simulate optlib in
        let static_opts' = new_static_opts results static_opts in
        compilation_cycle optlib (depth-1) static_opts'
;;

let random_compilation_cycle depth n = match n with 
    | 0 -> ();
    | _ ->
            ignore (run_simulations [] depth n []) ;
;;

let rec dumb_hillclimb_compilation_cycle depth static_opts = match depth with
    | 0 -> () ;
    | _ -> 
        let simulate opt = run_simulations [] 0 1 (opt :: static_opts) in
        let results = List.map simulate optlib in
        let static_opts' = new_static_opts results static_opts in
        dumb_hillclimb_compilation_cycle (depth-1) static_opts'
;;


type move = string
type state = { visits : int ; score : float ; moves : move list }
(* let max_iter = 2000 (* (List.length optlib) * (List.length optlib) *)
let debug = true
let max_depth = 10 *)

module MCTS = struct (* this should be generalised using an Ocaml functor *)
    type mctree = 
        | Unexplored of state * mctree list * move list
        | Explored   of state * mctree list
        | Terminal   of state
    ;;

    let get_state node =
        match node with
        | Unexplored (st, _, _)
        | Explored   (st, _)
        | Terminal    st         -> st
    ;;
    let get_children node =
        match node with
        | Unexplored (_, ch, _)
        | Explored   (_, ch)     -> ch
        | Terminal    _          -> failwith "No children"
    ;;
    let get_visits node =
        let st = get_state node in
        st.visits
    ;;

    let string_of_move move = move
    let move_of_node n =
        let st = get_state n in
        List.hd st.moves
    ;;

    let rec show_tree tree =
        let st = get_state tree in
        let pad = String.make (List.length st.moves) '\t' in
        let node = match st.moves with
            | []     -> "[]" ;
            | m :: _ -> string_of_move m 
        in
        Printf.printf "%s%s (%d %f)\n" pad node st.visits st.score ;
        match tree with
        | Terminal _            -> ()
        | Unexplored (_, ch, _)
        | Explored   (_, ch)    ->
                ignore (List.map show_tree ch)
    ;;


    let calculate_uct parent_state child = 
        let st = get_state child in
        let visits = float_of_int st.visits in
        let score = st.score in
        score /. visits +. sqrt ( 2.0 *. log (float_of_int parent_state.visits /. visits) )
    ;;
    let uct_select_child parent_st ns =
        let pairs = List.combine ( List.map (calculate_uct parent_st) ns ) ns in
        let uct_sort_nodes n1 n2 = compare (fst n1) (fst n2) in
        snd ( List.hd ( List.rev ( List.sort uct_sort_nodes pairs ) ) )
    ;;
    let replace_child children old nw =
        let replace old nw node = 
            match node == old with
            | true -> nw
            | false -> node
        in
        List.map (replace old nw) children
    ;;
    let update_state node score =
        let st = get_state node in
        let st' = { st with score = st.score +. score ; visits = st.visits + 1 } in
        match node with
        | Terminal _             -> Terminal st'
        | Explored (_, ch)       -> Explored (st', ch)
        | Unexplored (_, ch, un) -> Unexplored (st', ch, un)
    ;;

    let pick_untried_move (x::xs) = (x, xs)  (* hack: relies on possible moves being shuffled during initialisation *)
    let rnd_mv = random_opt
    let n_rnd_mvs = k_random_opts

    let score result =
        1.0 /. (result +. 1.0)
    ;;

    let run_simulation node =
        let st = get_state node in
        let static_opts = st.moves in
        let to_depth = settings.max_depth - (List.length static_opts) in
        let result =
            try score ( snd (run_simulations [] to_depth 1 static_opts) ) with
            | NoResults -> 0.0
        in
        result
    ;;
    let available_moves () =
        shuffle_list optlib
    ;;
    let new_node st mv =
        let moves = mv :: st.moves in
        let state = { visits=0 ; score=0.0 ; moves = mv::st.moves } in
        match List.length moves with
        | n when n == settings.max_depth -> 
                Terminal state
        | _ ->
                Unexplored (state, [], available_moves ())
    ;;
    let do_random_move node =
        match node with
        | Unexplored (st, children, untried) -> 
                let move, untried' = pick_untried_move untried in
                let child = new_node st move in
                let score = run_simulation child in
                let child' = update_state child score in
                child', untried', score
        | _ -> failwith "Next move is only valid for Unexplored nodes" 
    ;;
    let rec next_move node =
        try
            match node with
            | Terminal st ->
                    let score = run_simulation node in
                    (update_state node score), score
            | Explored (st, children) ->
                    let child = uct_select_child st children in
                    let child', score = next_move child in
                    let children' = replace_child children child child' in
                    let st' = get_state (update_state node score) in
                    Explored (st', children'), score
            | Unexplored (st, children, untried) ->
                    let new_child, untried', score = do_random_move node in
                    let st' = get_state (update_state node score) in
                    let children' = new_child :: children in
                    match children', untried' with
                    | _ , [] -> Explored   (st', children'), score
                    | _      -> Unexplored (st', children', untried'), score
        with
        | NoResults -> next_move node
    ;;

    let decide node =
        let children = get_children node in
        let srtfun a b = compare (get_visits b) (get_visits a) in
        List.hd (List.sort srtfun children)
    ;;

    let rec uct root n =
        print_endline "=====================================" ;
        Printf.printf "  Iterations remaining: %d\n" n ;
        print_endline "=====================================" ;
        match n with
        | 0 ->
                if settings.debug then show_tree root ;
                decide root
        | _ ->
                let root' = fst (next_move root) in
                uct root' (n-1)
    ;;
    let rec choose_moves rootnode iters depth =
        match depth with
        | 0 -> []
        | _ -> 
                let best_node = uct rootnode iters in
                let mv = move_of_node best_node in
                mv :: choose_moves best_node iters (depth-1) 
    ;;
end ;;

let mcts_compilation_cycle depth = 
    let rootnode = MCTS.Unexplored (
        { visits = 0 ; score = 0.0 ; moves = [] }, 
        [], MCTS.available_moves () 
    ) in
    let moves = MCTS.choose_moves rootnode settings.max_iter depth in
    List.iter (Printf.printf "%s, ") moves ;
    print_newline () ;
;;


let rec accepted_args = [
    (* long opt , shrt, arg?  , function                               , usage text *)
    ("--help"   , "-h", false , usage                                  , "Print this help text and exit") ;
    ("--depth"  , ""  , true  , (fun arg -> settings.max_depth <- int_of_string arg), "Set max length of pass sequence to <arg>") ;
    ("--iter"   , ""  , true  , (fun arg -> settings.max_iter <- int_of_string arg) , "Set maximum iterations to <arg>") ;
    ("--opt"    , ""  , true  , (fun arg -> settings.opt      <- arg)  , "Pass <arg> to the compiler") ;

    ("--tree"   , ""  , false , (fun arg -> settings.mode <- TreeSample), "Use tree search with random sampling (default behaviour)" ) ;
    ("--random" , ""  , false , (fun arg -> settings.mode <- Random)    , "Use random search" ) ;
    ("--hill"   , ""  , false , (fun arg -> settings.mode <- HillClimb) , "Use simple hill-climbing") ;
    ("--mcts"   , ""  , false , (fun arg -> settings.mode <- MCTS)      , "Use Monte-Carlo Tree Search") ;

    ("--debug"  , ""  , false , (fun arg -> settings.debug <- true)     , "Switch on debugging output" ) ;
] and usage _ =
    let string_of_arg (long, short, takes_arg, _, text) =
        let arg = if takes_arg then "<arg>" else "" in
        let sht = match short with | "" -> "" | _ -> sprintf "%s %s" short arg in
        printf "\t%s %s\t%s\t%s\n" long arg sht text
    in
    List.iter print_endline [
        "Usage: " ; Sys.argv.(0) ; " [args] <src>" ;
        "Where [args] can be: " ;
    ] ;
    List.iter string_of_arg accepted_args ;
    exit 0;
;;

let rec parse_args args = 
    match args with
    | [] -> ()
    | "--help" :: _ | "-h" :: _ -> usage "" ;

    | "--depth" :: d :: args' ->
            settings.max_depth <- int_of_string d ; parse_args args'
    | "--iter"  :: i :: args' ->
            settings.max_iter  <- int_of_string i ; parse_args args'
    | "--opt" :: arg :: args' ->
            settings.opt       <- arg ; parse_args args'

    | "--tree" :: args'   -> settings.mode <- TreeSample ; parse_args args'
    | "--random" :: args' -> settings.mode <- Random     ; parse_args args'
    | "--hill" :: args'   -> settings.mode <- HillClimb  ; parse_args args'
    | "--mcts" :: args'   -> settings.mode <- MCTS       ; parse_args args'

    | "--debug" :: args'  -> settings.debug     <- true      ; parse_args args'
    | filename :: []      -> settings.filename  <- filename  ; ()
    | _                   -> usage "" ;
;;

let main () = 
    Random.self_init () ;
    parse_args ( List.tl ( Array.to_list Sys.argv)) ;
    if settings.filename = "" then usage "" ;
    let starttime = int_of_float (Unix.time () ) in
    Printf.printf "Started at %d\n" starttime ;
    let _ = match settings.mode with
        | MCTS ->
            mcts_compilation_cycle settings.max_depth
        | TreeSample ->
            compilation_cycle optlib 10 []
        | Random -> 
            random_compilation_cycle 10 23500
        | HillClimb ->
            dumb_hillclimb_compilation_cycle 10 []
    in
    let endtime = int_of_float (Unix.time () ) in
    Printf.printf "Finished at %d\n" endtime ;
    Printf.printf "Total run-time was %d\n" (endtime - starttime) ;
    exit 0 ;
;;

main () ;
