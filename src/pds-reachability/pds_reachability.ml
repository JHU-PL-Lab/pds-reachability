(**
   This module is meant to test reachability in a push-down system which accepts
   by empty stack.
*)

module type Decorated_type = Pds_reachability_utils.Decorated_type;;
module type Basis = Pds_reachability_basis.Basis;;
module type Classifier = Pds_reachability_basis.State_classifier;;
module type Dynamic_pop_handler =
  Pds_reachability_types_stack.Dynamic_pop_handler
;;
module Make = Pds_reachability_analysis.Make;;
module Make_with_classifier = Pds_reachability_analysis.Make_with_classifier;;
