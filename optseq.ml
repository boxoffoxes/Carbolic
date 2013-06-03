open Str 
open Unix

type settings = {
    mutable src:string ;
    mutable asm:string ;
    mutable obj:string ;
    mutable bin:string ;
    mutable opt_src:string ;
    mutable opt_cmd:string array ;
    mutable opt_lib:string ;
    mutable work_dir:string ;
    mutable compile_cmd:string array ;
    mutable verbose:bool ;
}


let _optimised_src = "optimised.ll"
let _binary = "a.out"
let settings = {
    src = "" ;
    asm = "optimised.s" ;
    obj = "optimised.o" ;
    bin = _binary ;
    opt_src = _optimised_src ;
    opt_cmd = [| "/usr/bin/opt" ; "-S" ; "-o" ; _optimised_src |] ;
    opt_lib = "Doc/all-opts.txt" ;
    work_dir = "./work" ;
    compile_cmd = [| "" ; "-o" ; _binary |] ;
    verbose = false ;
}

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

let create_pathname_from_opts opts = 
    Digest.to_hex ( Digest.string ( String.concat " " (Array.to_list opts ) ) )
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

let create_path path =
    Unix.mkdir path 0o755 ;
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

let with_path path f =
    let cwd = Sys.getcwd () in
    create_path path ;
    Sys.chdir path ;
    let v = f () in
    Sys.chdir cwd ;
    v
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


(** {1 Running simulations} *)

(** Run @param n simulations with @param static_opts and @param k random
 * optimisations *)
let rec run_simulation optlib n k static_opts = match n with
    | 0 -> ()
    | _ -> (
        let ropts = n_random_opts k optlib in
        let precmd = [| "/bin/ln" ; "-s" ; String.concat "" [ "../" ; settings.src ] ; "./" |] in
        let optcmd = Array.concat [
            [| "/usr/bin/opt" ; "-S" |] ;
            static_opts ; ropts ; 
            [| "-o" ; settings.opt_src ; settings.src |] 
        ] in
        let cmpcmd = [| "/usr/bin/clang" ; "-O0" ; "-pipe" ; "-lc" ; "-lm" ; "-o" ; settings.bin ; settings.opt_src |] in
(*        let asmcmd = [| "/usr/bin/as" ; "-o" ; settings.obj ; settings.asm |] in
        let lnkcmd = [| "/usr/bin/clang" ; "-O0" ; "-o" ; settings.bin ; "-lc" ; "-lm" ; settings.obj |] in *)
        let compile () = 
            run_child_process precmd ;
            run_child_process optcmd ;
            run_child_process cmpcmd ; 
        in
        let wd = create_pathname_from_opts ropts in

        with_path wd compile ;
        run_simulation optlib (n-1) k static_opts ;
    )
;;

(** Run @param n simulations, using @param k randomly selected optimisations pulled from
 * @param optlib, and including @param static_opts at the head of the list of
 * optimisations for every simulation. *)
let run_simulations optlib static_opts k n =
    let sim pass = run_simulation optlib n k [| pass |] in
    let cwd = Sys.getcwd () in
    Sys.chdir settings.work_dir ;
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

let usage () =
    List.iter print_string [
        "Usage: " ; Sys.argv.(0) ; " [args] <source_file.ll>\n" ;
        "Where [args] can be: \n" ;
        "\t-d working_dir   (default: " ; settings.work_dir ; ")\n" ;
        "\t-o binary_name   (default: " ; settings.bin ; ")\n" ;
        "\t-l opt_library   (default: " ; settings.opt_lib ; ")\n" ;
        "\t-n optimised_src (default: " ; settings.opt_src ; ")\n" ;
    ] ;
    exit 0;
;;

let rec parse_args args = match args with
    | [] -> usage () ;
    | s :: [] -> settings.src <- s ;
    | "-o" :: arg :: args' -> 
        settings.bin <- arg ;
        parse_args args'
    | "-l" :: arg :: args' -> 
        settings.opt_lib <- arg ;
        parse_args args'
    | "-n" :: arg :: args' ->
        settings.opt_src <- arg ;
    | "-d" :: arg :: args' -> 
        settings.work_dir <- arg ;
    | "-v" :: args' ->
        settings.verbose <- true ;
    | _ -> usage () ; (* this is a hack to fool the type system *)
;;

let main () =
    let cksums = Hashtbl.create 1000 in
    let args = List.tl (Array.to_list Sys.argv) in
    parse_args args ;
    let optlib = load_optlib settings.opt_lib in
    Random.self_init () ;

    run_simulations optlib [| "-lint" ; "-roller" |]  10 100 ;
;;

(* let opts = extract_opts <<- read_file_to_list "Doc/all-opts.txt" ;;

 ;; *)


main ()
