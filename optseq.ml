open Str 
open Unix

type settings = {
    src:string ;
    bin:string ;
    opt_src:string ;
    opt_cmd:string array ;
    compile_cmd:string array ;
}


let default_opt_src = "optimised.ll"
let default_opt_cmd = [| "/usr/bin/opt" ; "-S" ; "-o" ; optimised_src |]

let default_bin = "a.out"
let compile_cmd = [| "" ; "-o" ; binary |]

(** {1 Utility functions} *)

let read_file_to_list filename =
    let lines = ref [] in
    let chan = open_in filename in
    try
        while true; do
            lines := input_line chan :: !lines
        done;
        []
    with End_of_file ->
        close_in chan;
        List.rev !lines
;;


let run_child_process args =
    (* Get the name of the executable from the first arg *)
    let cmd = args.(0) in
    let pid = fork () in
    match pid with
    | 0 -> Unix.execv cmd args ;
    | -1 -> raise ( Failure "Failed to run program!" )
    | _ -> ignore ( wait () ) ;
;;

let show_commandline a =
    let print_elem = function word -> print_string word ; print_string " " ; in
    Array.iter print_elem a ;
    (* ignore ( Array.map Digest.string a ) ; *)
    print_newline () ;
;;

let checksum file =
    Digest.file file
;;


(** {1 Generating random option lists} *)

let load_optlib filename =
    let lines = read_file_to_list filename in
    let rex = Str.regexp " +" in
    let first_word str = List.hd ( Str.split rex str ) in
    Array.of_list ( List.map first_word lines )
;;

let random_opt optlib =
    let sz = Array.length optlib in
    let i = Random.int sz in
    optlib.(i)
;;

let rec n_random_opts n optlib =
    let ropts = Array.make n "" in
    for i=0 to n-1 do
        ropts.(i) <- random_opt optlib
    done ;
    ropts
;;

(** {1 Generating optimised binaries} *)

let optimise opts =
    let cmdline = Array.concat [ opt_cmd ; opts ] in
    run_child_process cmdline ;
    checksum optimised_src
;;

let compile () =
    let cmdline = compile_cmd in
    run_child_process cmdline ;
    checksum binary
;;


(** {1 Running simulations} *)

(** Run @param n simulations with @param static_opts and @param k random
 * optimisations *)
let rec run_simulation optlib n k static_opts = match n with
    | 0 -> ()
    | _ -> (
        let ropts = n_random_opts k optlib in
        let cmdline = Array.concat [ opt_cmd ; [| static_opts |] ; ropts ] in
        show_commandline cmdline ;
        run_simulation optlib (n-1) k static_opts ;
    )
;;

(** Run @param n simulations, using @param k randomly selected optimisations pulled from
 * @param optlib, and including @param static_opts at the head of the list of
 * optimisations for every simulation. *)
let run_simulations optlib static_opts k n =
    let sim = run_simulation optlib n k in
    Array.iter sim optlib ;
;;




(** {1 Benchmarking compiled executables} *)

(* TODO: don't bother executing programs with the same MD5 sum as previously
 * benchmarked programs as they will have identical performance characteristics.
 * Should offer a performance hike, particularly for simple programs. *)

let benchmark_prog args =
    let a = fork () in
    match a with
    | 0 -> (
        run_child_process args ;
        let t = Unix.times () in
        print_string "( " ;
        print_float t.Unix.tms_cstime ;
        print_string ", " ;
        print_float t.Unix.tms_cutime ;
        print_endline " )" ;
        exit 0 ;
    )
    | -1 -> raise ( Failure "Failed to fork a child process!" )
    | _  -> ignore ( wait () ) ;
;;


(** {1 Program entry point and commandline parsing} *)

let parse_args () =
    
;;

let main () =
    let (optlib, ll_src) = parse_args  in
    let cksums = Hashtbl.create 1000 in
    Random.self_init () ;

    benchmark_prog [| "/bin/ls" ; "-al" |] ;

    run_simulations optlib [| "-lint" ; "-roller" |]  10 100 ;
;;

(* let opts = extract_opts <<- read_file_to_list "Doc/all-opts.txt" ;;

 ;; *)


main ()
