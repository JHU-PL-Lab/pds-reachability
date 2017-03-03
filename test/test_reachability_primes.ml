(**
   This test module performs a series of operations to test the PDA reachability
   functionality in the Odefa analysis library.
*)

open Batteries;;
open Jhupllib;;
open OUnit2;;

let lazy_logger = Logger_utils.make_lazy_logger "Test_reachability";;

open Pds_reachability_types_stack;;

type state =
  | Number of int
  | Count of int
;;

(*TODO: I'm sure I have to change these things to match the
  new type but I'm not sure how*)
module Test_state =
struct
  type t = state
  let equal = (==)
  let compare = compare
  let pp = Format.pp_print_int
  let show = string_of_int
  let to_yojson n = `Int n
end;;

type stack_elt =
  | Bottom of char
  | Prime of int
;;

(*TODO: I'm sure I have to change these things to match the
  new type but I'm not sure how*)
module Test_stack_element =
struct
  type t = stack_elt
  let equal = (==)
  let comapre = compare
  let pp fmt c = Format.pp_print_string fmt (String.make 1 c)
  let show c = String.make 1 c
  let to_yojson c = `String (String.make 1 c)
end;;

module Test_spec =
struct
  module State = Test_state
  module Stack_element = Test_stack_element
end;;
