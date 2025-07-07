(* This file is part of Bisect_ppx, released under the MIT license. See
   LICENSE.md for details, or visit
   https://github.com/aantron/bisect_ppx/blob/master/LICENSE.md. *)

module Node = struct
  module Fs = struct
    type path = string

    external openSync :
    path ->
    (
      [ `Read [@bs.as "r"]
      | `Read_write [@bs.as "r+"]
      | `Read_write_sync [@bs.as "rs+"]
      | `Write [@bs.as "w"]
      | `Write_fail_if_exists [@bs.as "wx"]
      | `Write_read [@bs.as "w+"]
      | `Write_read_fail_if_exists [@bs.as "wx+"]
      | `Append [@bs.as "a"]
      | `Append_fail_if_exists [@bs.as "ax"]
      | `Append_read [@bs.as "a+"]
      | `Append_read_fail_if_exists [@bs.as "ax+"]
      ] [@bs.string]) ->
    unit = "openSync"  [@@bs.module "fs"]

    type encoding =
    [
      `hex
    | `utf8
    | `ascii
    | `latin1
    | `base64
    | `ucs2
    | `base64
    | `binary
    | `utf16le ]

    external writeFileSync :
      string ->
      string ->
      encoding ->
      unit = "writeFileSync"
    [@@bs.val] [@@bs.module "fs"]

    end
end

module Buffer = struct
  type t = {
    mutable contents : string;
  }
  let make () = {contents = ""}
  let add t str = t.contents <- t.contents ^ str
  let contents t = t.contents
end

type instrumented_file = {
  filename : string;
  points : int array;
  counts : int array;
}

type coverage = (string, instrumented_file) Hashtbl.t

let coverage_file_identifier = "BISECT-COVERAGE-4"

let write_int buf i =
  Buffer.add buf (" " ^ (string_of_int i))

let write_string buf s =
  Buffer.add buf (" " ^ (string_of_int (String.length s)) ^ " " ^ s)

let write_array write_element buf a =
  Buffer.add buf (" " ^ (string_of_int (Array.length a)));
  Array.iter (write_element buf) a

let write_list write_element buf l =
  Buffer.add buf (" " ^ (string_of_int (List.length l)));
  List.iter (write_element buf) l

let write_instrumented_file buf {filename; points; counts} =
  write_string buf filename;
  write_array write_int buf points;
  write_array write_int buf counts

let write_coverage buf coverage =
  Buffer.add buf coverage_file_identifier;
  write_list write_instrumented_file buf coverage

(** Helpers for serializing the coverage data in {!coverage}. *)
let flatten_coverage coverage =
  Hashtbl.fold (fun _ file acc -> file::acc) coverage []

let coverage : coverage Lazy.t =
  lazy (Hashtbl.create 17)

let flatten_data () =
  flatten_coverage (Lazy.force coverage)

let runtime_data_to_string () =
  match flatten_data () with
  | [] ->
    None
  | data ->
    let buf = Buffer.make () in
    write_coverage buf data;
    Some (Buffer.contents buf)


let get_coverage_data =
  runtime_data_to_string

let prng =
  Random.State.make_self_init () [@coverage off]

let random_filename ~prefix =
  let numStr = (string_of_int (abs (Random.State.int prng 1000000000))) in
  let paddedStr = (Js.String2.repeat "0" (9 - String.length numStr)) ^ numStr in
  prefix ^ paddedStr ^ ".coverage"

let write_coverage_data () =
  match get_coverage_data () with
  | None ->
    ()
  | Some data ->
    let rec create_file attempts =
      let filename = random_filename ~prefix:"bisect" in
      match Node.Fs.openSync filename `Write_fail_if_exists with
      | exception exn ->
        if attempts = 0 then
          raise exn
        else
          create_file (attempts - 1)
      | _ ->
        Node.Fs.writeFileSync filename data `binary
    in
    create_file 100

let reset_counters () =
  Lazy.force coverage
  |> Hashtbl.iter begin fun _ {counts; _} ->
    match Array.length counts with
    | 0 -> ()
    | n -> Array.fill counts 0 (n - 1) 0
  end

let reset_coverage_data =
  reset_counters

let node_at_exit : (unit -> unit) -> unit = [%bs.raw {|
  function (callback) {
    if (typeof process !== 'undefined' && typeof process.on !== 'undefined')
      process.on("exit", callback);
  }
|}]

let exit_hook_added = ref false

let write_coverage_data_on_exit () =
  if not !exit_hook_added then begin
    node_at_exit (fun () -> 
      write_coverage_data (); 
      reset_coverage_data (); 
      ()
    );
    exit_hook_added := true
  end

let register_file ~filename ~points =
  let counts = Array.make (Array.length points) 0 in
  let coverage = Lazy.force coverage in
  if not (Hashtbl.mem coverage filename) then
    Hashtbl.add coverage filename {filename; points; counts};
  `Visit (fun index ->
    let current_count = counts.(index) in
    if current_count < max_int then
      counts.(index) <- current_count + 1)


let register_file
    ~bisect_file:_ ~bisect_silent:_ ~bisect_sigterm:_ ~filename ~points =
  write_coverage_data_on_exit ();
  register_file ~filename ~points
