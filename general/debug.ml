(*
   Collection of functions used across the code base for debugging-related activities.
   Nik Sultana, Cambridge University Computer Lab, July 2015

   Use of this source code is governed by the Apache 2.0 license; see LICENSE
*)

open Lexing

(*Format a list of strings nicely*)
let print_list indentation l =
  let sep = "\n" ^ indentation ^ "\t" in
  if l = [] then "(empty)"
  else sep ^ String.concat sep l

(*This is used to avoid committing to a specific (i.e., string in this case)
  type. I use it in instances when x is already a string, so the runtime system
  shouldn't have to do anything.*)
let stringify (x : 'a) : string =
  if Obj.tag (Obj.repr x) = Obj.string_tag then
    Obj.magic x
  else if Obj.tag (Obj.repr x) = Obj.int_tag then
    string_of_int (Obj.magic x)
  else failwith "stringify over unknown type"

let print_position outx lexbuf =
  let pos = lexbuf.lex_curr_p in
  Printf.fprintf outx "%s:%d:%d" pos.pos_fname
    pos.pos_lnum (lexbuf.lex_start_pos - pos.pos_bol + 1)
