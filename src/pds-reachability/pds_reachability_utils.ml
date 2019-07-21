(**
   This module contains some convenient definitions used throughout the rest
   of this library.
*)

open Jhupllib;;

(**
   A type for modules which carry a value type along with a few common
   operations on that type.
*)
module type Decorated_type =
sig
  type t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val pp : t Pp_utils.pretty_printer
  val show : t -> string
  val to_yojson : t -> Yojson.Safe.t
end;;

module Unit : Decorated_type with type t = unit =
struct
  type t = unit [@@deriving to_yojson];;
  let equal _ _ = true;;
  let compare _ _ = 0;;
  let pp formatter () = Format.pp_print_string formatter "()";;
  let show () = "()";;
end;;
