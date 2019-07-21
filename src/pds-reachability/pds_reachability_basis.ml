(*
   This module defines a module type signature used as the basis for the PDS
   reachability functor.
*)

open Pds_reachability_utils;;

(**
   A module type which serves as the basis for the functor which builds the
   PDS reachability implementation.
*)
module type Basis =
sig
  module State : Decorated_type
  module Stack_element : Decorated_type
end;;

(**
   A module type which describes how states may be classified.  Classification
   is used for performance purposes; it is possible for an edge function to be
   applied only to states of a particular class.  In the simplest case, all
   states may be classified to unit.
*)
module type State_classifier =
sig
  module State : Decorated_type;;
  module Class : Decorated_type;;
  val classify : State.t -> Class.t;;
end;;
