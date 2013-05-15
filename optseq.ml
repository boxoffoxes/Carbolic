open Str 
open Unix


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
    (* TODO: Don't forget that cmd needs to be duplicated as args.(0) for execv! *)
    let cmd = args.(0) in
    let pid = fork () in
    match pid with
    | 0 -> Unix.execv cmd args ;
    | -1 -> raise ( Failure "Failed to run program!" )
    | _ -> ignore ( wait () ) ;
;;


(** {1 Generating random option lists} *)

let extract_opts l =
    let rex = Str.regexp " +" in
    let first_word str = List.hd ( Str.split rex str ) in
    Array.of_list ( List.map first_word l )
;;

let random_opt opts =
    let sz = Array.length opts in
    let i = Random.int sz in
    opts.(i)
;;

let rec n_random_opts n opts =
    match n with 
    | 0 -> []
    | _ -> ( random_opt opts ) :: (n_random_opts (n - 1) opts)
;;


(** {1 Benchmarking compiled executables} *)

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


(** {1 Program entry point} *)

let main () =
    let lines = read_file_to_list "Doc/all-opts.txt" in
    let opts = extract_opts lines in
    Random.self_init () ;
    ignore ( List.map print_endline ( n_random_opts 25 opts ) ) ;
    print_newline ();

    benchmark_prog [| "/bin/ls" ; "-al" |] ;
;;

(* let opts = extract_opts <<- read_file_to_list "Doc/all-opts.txt" ;;

 ;; *)

main ()
