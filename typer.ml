open Ast
open Tast
open Misc

exception TypeError of loc * string
module Smap = Map.Make(String)
module Couple = struct
  type t = (string * string)
  let compare = Pervasives.compare
end

module Cset = Set.Make(Couple)

(* L'environnement vide *)
let env0 () = 
  {
    classes = [];
    constrs = [];
    vars    = [];
    meths   = []
  }

(* La substitution triviale *)
let subst0 () =
  let init = [
    "Any",      Tany;
    "AnyVal",   TanyVal;
    "Boolean",  Tboolean;
    "Int",      Tint;
    "Unit",     Tunit;
    "AnyRef",   TanyRef;
    "String",   Tstring;
    "Null",     Tnull;
    "Nothing",  Tnothing;
    ] in
  List.fold_left (fun m (id, t) -> Smap.add id t m) Smap.empty init  

(* tparam_type list -> typerType list -> substitution *)
let subst_from_lists tpts ts = 
  let rec aux m = function 
    | [], []          ->  m
    | t1::q1, t2::q2  ->  Smap.add (get_tpt_id t1) t2 (aux m (q1, q2)) 
    | _               ->  failwith "Les listes tptcs et ts n'ont pas la même
    longueur dans subst_from_lists, ce n'est pas normal"
  in aux Smap.empty (tpts, ts)

(* Ajoute une variable à un environnement *)
(* env -> context_var -> env *)
let add_var_env env cv = 
  {
    classes = env.classes ;
    constrs = env.constrs ;
    vars    = cv::env.vars;
    meths   = env.meths 
  }

(* Idem avec un tvar
 * context -> tvar -> context *)
let add_tvar_env env tv = 
  let cv = match tv.tv_cont with
    | TVal (i, t, _) -> CVal (i, t)
    | TVar (i, t, _) -> CVar (i, t)
  in add_var_env env cv

(* Ajoute une classe a un environnement
 * context -> tclasse -> context *)
let add_classe_env env c = 
  {
    classes = c::env.classes;
    constrs = env.constrs ; 
    vars    = env.vars;
    meths   = env.meths
  }

(* Ajoute une contrainte a un environnement
 * context -> (ident * typerType) -> context *)
let add_constr_env env constr = 
  {
    classes = env.classes;
    constrs = constr::env.constrs;
    vars    = env.vars;
    meths   = env.meths
  }

(* Ajoute une méthode à un environnement.
 * context -> tmethode -> context *)
let add_tmeth_env env tm =
  {
    classes = env.classes;
    constrs = env.constrs;
    vars    = env.vars;
    meths   = tm::env.meths
  }

(* Le type Array[String]
 * loc -> tclasse *)
let array_tc l =
  let tptcs = [{
    tptc_cont = TPTCrien {
      tpt_cont = ("S", None);
      tpt_loc = l 
      };
    tptc_loc = l
    }] in {
  cc_name   = "Array";
  cc_tptcs  = tptcs;
  cc_params = [];
  cc_deriv  = None;
  cc_env = (add_classe_env (env0 ()) {
    cc_name   = "S";
    cc_tptcs  = [];
    cc_params = [];
    cc_deriv  = None;
    cc_env    = env0 ()
  })
}

(* chercher une classe dans l'environnement env *)
let classe_lookup env id = 
  let rec aux = function
    | []      -> raise Not_found
    | c::q    -> if c.cc_name = id then
                   c
                 else
                   aux q
  in aux env.classes

(* Ajout d'une valeur à une substitution en vue d'une composition .*)
let rec add_one_key id t m = 
  let f = function
    | Tclasse (cid, s) ->
        if cid = id then
          t
        else
          Tclasse (cid, add_one_key id t s)          
    | t' -> t'
  in let m' = Smap.map f m in
  Smap.add id t m'

(* Composition des substitutions *)
let rec subst_compose s s' = Smap.fold add_one_key s s'

(* fonction de substitution
 * subst : context -> substitution -> typerType -> typerType *)
let rec subst env s = function
  | Tclasse (cid, s') ->
      begin try 
          Smap.find cid s
      with  
        | Not_found -> Tclasse (cid, subst_compose s s')
      end
  | t -> t 

(* Idem mais mais applicable à un id.
 * /!\ Doit servir uniquement à substituer un paramètre de type
 * subst_id -> context -> substitution -> ident -> typerType *)
let subst_id env s id = subst env s (Tclasse (id, subst0 ()))

(************************
 * 2 PRINTING FUNCTIONS *
 ************************)

(* Affichage d'un type *)
let rec string_of_typ env = function
  | Tany ->         "Any"
  | TanyVal ->      "AnyVal"
  | Tboolean ->     "Boolean"
  | Tint ->         "Int"
  | Tunit ->        "Unit"
  | TanyRef ->      "AnyRef"
  | Tstring ->      "String"
  | Tnull ->        "Null"
  | Tnothing ->     "Nothing"
  | Tclasse (cid, s) ->
                    string_of_class env cid s

(* Affichage d'une classe *)
and string_of_class env i sub =
  i^"["^(
  List.fold_left (fun s t -> s^(string_of_typ env t)^", ") ""
    (List.map (subst_id env sub) (get_tptc_id_list (try classe_lookup env i with
    | Not_found -> failwith ("c'est qui "^i^" ?")).cc_tptcs))
  )^"]"

(* context -> typ -> typerType *)
let rec typerType_of_typ env t = match t.t_name with
  | "Any"     ->  Tany
  | "AnyVal"  ->  TanyVal
  | "Boolean" ->  Tboolean
  | "Int"     ->  Tint
  | "Unit"    ->  Tunit
  | "AnyRef"  ->  TanyRef
  | "String"  ->  Tstring
  | "Null"    ->  Tnull
  | "Nothing" ->  Tnothing
  | "Array"   ->  Tclasse ("Array", Smap.add "S" Tstring (subst0 ()))
  | s         ->  let c = begin try
                    classe_lookup env s
                  with
                    | Not_found -> raise (TypeError (t.t_loc, "La
                    classe \""^s^"\" n'existe pas"))
                  end in
                  let args = get_list t.args_type.at_cont in
                  Tclasse (c.cc_name, subst_compose
                    (subst_from_lists
                      (List.map tpt_of_tptc c.cc_tptcs)
                      (List.map (typerType_of_typ env) args))
                    (subst0 ()))
        
(* arguments_type -> targuments_type *)
let targst_of_argst env a =
  let l = match a.at_cont with
    | None -> []
    | Some l' -> List.map (typerType_of_typ env) l'
  in { tat_cont = l; tat_loc = a.at_loc }

(* Recherche de la déclaration d'une variable dans une var list *)
(* ident -> tvar list -> typerType *)
let var_lookup id env = 
  let rec aux = function
    | []    ->  raise Not_found 
    | cv::q ->  begin match cv with
                  | CVar (i, t) ->  if i = id then
                                      t
                                    else
                                      aux q
                  | CVal (i, t) ->  if i = id then
                                      t
                                    else
                                      aux q
    end in aux env.vars

(* context -> loc -> typerType -> (bool, loc) option
  * covariant (+)     = Some (true, pos)
  * contravariant (-) = Some (false, pos)
  * sans variance     = None
  *)
let variance env = function
  | Tclasse(i, _) -> 
      (* Realy need explanations here *)
      let tptc_list = try begin match var_lookup "this" env with
          | Tclasse(i', _) ->
              let c = begin try
                classe_lookup env i'
              with
                | Not_found -> failwith ("La classe \""^i'^"\"
                n'existe pas")
              end in
              c.cc_tptcs
          | _ -> []
        end with
          | Not_found -> []
      in let rec aux = function
        | [] -> None
        | tptc::q -> begin match tptc.tptc_cont with
              | TPTCplus tpt ->
                  if i = fst tpt.tpt_cont then Some (true, tpt.tpt_loc) else aux q
              | TPTCmoins tpt ->
                  if i = fst tpt.tpt_cont then Some (false, tpt.tpt_loc) else aux q
              | TPTCrien  tpt ->
                  if i = fst tpt.tpt_cont then None else aux q
        end in aux tptc_list
  | _ -> None

(* variance_test_vars : context -> unit *)
let variance_test_vars env =
  List.iter (fun cv -> match cv with
      | CVar (_, t) -> begin match variance env t with
            | None -> ()
            | Some (b, eloc) ->
                if b then
                  raise (TypeError(eloc, "E01 : Cette variable de type est
                  covariante et apparaît dans un position neutre"))
                else
                  raise (TypeError(eloc, "E02 : Cette variable de type est
                  contravariante et apparaît dans un position neutre"))
          end
      | CVal (_, t) -> begin match variance env t with
            | None -> ()
            | Some (b, eloc) ->
                if not b then
                  raise (TypeError(eloc, "E03 : Cette variable de type est
                  contravariante et apparaît dans un position positive"))
      end
    ) env.vars

(* context -> unit *)
let variance_test_meths env = 
  List.iter (fun tm -> match variance env tm.tm_res_type with
          | None -> ()
          | Some (b ,eloc) ->
              if not b then
                raise (TypeError (eloc, "E04 : Cette variable est contravariante
                et apparait dans une position positive"));
          List.iter (fun tp -> begin match variance env tp.tp_typ with
                | None -> ()
                | Some (b, eloc) ->
                    if b then
                      raise (TypeError (eloc, "E05 : Cette variable est
                      covariante et apparaît dans une position négative"))
                end) tm.tm_params
    ) env.meths


(* ident -> tclasse -> tmethode *)
let meth_lookup m_id env =
  let rec aux = function 
    | []   -> raise Not_found
    | m::q ->
        if m.tm_name = m_id then
          m
        else
          aux q
  in aux env.meths

(* Fonction auxiliaire qui vérifie qu'une
 * classe hérite d'une autre (indirectement) *)
let herits_from env loc0 cid1 cid2 = 
  let rec herits_from_c2 cid = 
    if cid = cid2 then
      true
    else begin
      let c = try
        classe_lookup env cid
      with
        | Not_found -> failwith ("Pas censé arriver là dans herits_from : c'est
        qui "^cid^" ?")
      in
      match c.cc_deriv with
      | Some (t, _) -> begin match t with
            | Tclasse (cid', _) -> 
                let c' = begin try 
                  classe_lookup env cid'
                with 
                  | Not_found -> raise (TypeError (loc0, "La classe \""^cid'^"\"
                  n'existe pas"))
                end in
                herits_from_c2 c'.cc_name
            | _ -> false
          end 
      | None -> false
    end in herits_from_c2 cid1
    
(* Sous-typage *)
let rec is_sstype env loc0 t1 t2 = match (t1, t2) with
  | Tnothing, _             -> true
  | Tnull,  Tclasse (_, _)  -> true
  | Tnull, Tstring          -> true 
  | _, TanyVal              -> t1 = Tint || t1 = Tunit || t1 = Tboolean 
  | _, Tany                 -> true
  | _, TanyRef              -> begin match t1 with
                                 | Tclasse (_, _)   -> true
                                 | Tstring | Tnull  -> true
                                 | _                -> false
                               end
  | Tclasse (cid1, s1), Tclasse (cid2, s2) ->
      (* Cas où cid1 = cid2, on doit vérifier les contraintes sur les paramètres de
       * type *)
      if (cid1 = cid2) then begin
        let welltyped = ref true in
        (* typerType list -> typerType list -> tparam_type_classeCont list -> () *)
        let f t1 t2 = function 
          | TPTCplus  tpt -> welltyped := !welltyped && (is_sstype env loc0 t1 t2)
          | TPTCrien  tpt -> welltyped := !welltyped && (t1 = t2)
          | TPTCmoins tpt -> welltyped := !welltyped && (is_sstype env loc0 t2 t1)
        in
        let c1  = begin try
          classe_lookup env cid1
        with
          | Not_found -> failwith "C'est quoi ce bins ?"
        end in
        let ts1 = List.map (subst_id env s1) (get_tptc_id_list c1.cc_tptcs) in
        let c2  = begin try
          classe_lookup env cid2
        with
          | Not_found -> failwith "C'est quoi ce bins 2 ?"
        end in
        let ts2 = List.map (subst_id env s2) (get_tptc_id_list c2.cc_tptcs) in
        let tptcs = List.map (fun tptc -> tptc.tptc_cont) c1.cc_tptcs
        in
        iter3 f ts1 ts2 tptcs;
        !welltyped
      (* Cas où cid1 <> cid2.
       * On distingue selon si cid1 hérite de cid2 ou non. *)
      end else begin
        if herits_from env loc0 cid1 cid2 then begin
          let c1 = begin try
            classe_lookup env cid1
          with
            | Not_found -> failwith "C'est quoi ce bins 3 ?"
          end in
          let (cid, s) = begin match c1.cc_deriv with
            | Some (Tclasse (cid, s), _) -> (cid, s)
            | _ -> failwith "On ne peut que trouver une classe ici : herits_from
                      vient de renvoyer true."
          end in
          is_sstype env loc0 (Tclasse (cid, subst_compose s1 s)) t2 end
        else begin
          try 
            is_sstype env loc0 t1 (List.assoc cid2 env.constrs)
          with 
            | Not_found -> false
        end
      end
  | t1, t2 -> t1 = t2

let max_type env t1 t2 eloc = 
    if is_sstype env eloc t1 t2 then t2
        else if is_sstype env eloc t2 t1 then t1
            else raise (TypeError (eloc, "Les deux types dans cette expression
            ne sont pas comparables."))

(* Respect d'une borne
 * context -> (typerType -> typerType) -> typerType -> (borne option * loc) ->
   * loc option
 * où borne = tparam_type_heritage *)
let check_borne env s tpt = match snd tpt.tpt_cont with
  | None    -> None
  | Some b  ->
      let t = subst_id env s (fst tpt.tpt_cont) in
      if (match b with
        | HTinf t' -> is_sstype env tpt.tpt_loc (subst env s t') t
        | HTsup t' -> is_sstype env tpt.tpt_loc t (subst env s t')
      ) then None
      else (Some tpt.tpt_loc)

(* Bonne formation d'une substitution.
 * Renvoie None si s est bien formée et Some eloc où eloc est la position de
 * l'erreur sinon.
 * context -> tparam_type_classe list -> substitution -> loc option *)
let is_subst_bf env tpts s =
  List.fold_left (fun eo tpt -> match eo with
      | None -> check_borne env s tpt
      | Some eloc -> Some eloc
    ) None tpts

(* Bonne formation d'une type.
 * Renvoie None si le type est bien formé et Some eloc où eloc est la position
 * de l'erreur sinon.
 * context -> typerType -> loc option *)
let rec is_bf env loc0 = function
  | Tclasse (cid, s)  ->
      begin try 
        (* On vérifie si la classe est dans l'environnement *)
        let c = begin try
          classe_lookup env cid 
        with
          | Not_found -> raise (TypeError (loc0, "La classe \""^cid^"\" est
              inconnue."))
        end in
        (* On vérifie que la substitution est bien formée *)
        begin match is_subst_bf env (List.map tpt_of_tptc c.cc_tptcs) s with
          (* On vérifie récursivement si les types permettant d'instancier la
           * classe sont bien définis. *)
          | None   -> 
              List.fold_left (fun eo t -> match eo with
                  | Some eloc ->  Some eloc
                  | None      ->  is_bf env loc0 t
                ) None (List.map (subst_id env s) (get_tptc_id_list c.cc_tptcs))
          (* La substitution n'est pas bien formée. *)
          | Some eloc -> Some eloc
        end
      with
        | Not_found -> failwith ("On a oublié d'ajouter la classe \""^cid^"\" à
            l'environnement à ce moment là")
        | Invalid_argument _ ->
            failwith "Pas censé arriver là"
      end
  | _ -> None


(* Typage à proprement parler *)

(* Typage des expressions *)
let rec type_expr env tro e = match e.e_cont with
  | Evoid         -> { te_cont = TEvoid ;
                       te_loc = e.e_loc ;
                       te_typ = Tunit }
  | Eint i        -> { te_cont = TEint i;
                       te_loc = e.e_loc ;
                       te_typ = Tint }
  | Estr s        -> { te_cont = TEstr s ;
                       te_loc = e.e_loc ;
                       te_typ = Tstring }
  | Ebool b       -> { te_cont = TEbool b;
                       te_loc = e.e_loc ;
                       te_typ = Tboolean }
  | Enull         -> { te_cont = TEnull ;
                       te_loc = e.e_loc ;
                       te_typ = Tnull }
  | Ethis         ->  begin try {
                        te_cont = TEthis;
                        te_loc = e.e_loc;
                        te_typ = var_lookup "this" env }
                      with
                        | Not_found ->  raise (TypeError (e.e_loc, "impossible
                          de déterminer à quoi \"this\" fait référence"))
                      end
  | Eacc a      -> begin match a.a_cont with
                     | Aident id -> 
                         begin try {
                           te_cont = TEacc (tacces_of_acces a);
                           te_loc = e.e_loc;
                           te_typ = var_lookup id env }
                         with
                           | Not_found ->
                                   type_expr env tro {
                                     e_cont = Eacc {
                                       a_cont = Aexpr_ident ({
                                         e_cont = Ethis;
                                         e_loc = a.a_loc
                                        }, id);
                                       a_loc = a.a_loc
                                     };
                                     e_loc = e.e_loc
                                   }
                         end
                     | Aexpr_ident (e',x) ->
                         let e'' = type_expr env tro e' in
                         (* Il faut que e'' soit une instance d'une classe *)
                         begin match e''.te_typ with
                           | Tclasse (cid, s) ->
                              let c = begin try 
                                classe_lookup env cid
                              with
                                | Not_found -> raise (TypeError (e''.te_loc, "La
                                    classe \""^cid^"\" n'existe pas"))
                              end in  
                               (* x doit faire référence à une variable
                                * existante, var_lookup soulève une
                                * erreur sinon *)
                               let t = begin try 
                                 var_lookup x c.cc_env
                               with
                                 | Not_found ->  raise (TypeError
                                     (e'.e_loc, "La classe de cette expression
                                     n'a pas de champ \""^x^"\"."))
                               end in 
                               {
                                 te_cont = TEacc {
                                     ta_cont = TAexpr_ident (e'', x);
                                     ta_loc = a.a_loc
                                   };
                                 te_loc = e.e_loc;
                                 te_typ = subst env s t
                               }
                           | _ ->  raise (TypeError (e.e_loc, "Cette
                               expression n'est pas une instance d'une classe,
                               elle ne peut avoir de champ \""^x^"\"."))
                         end
                   end
  | Eacc_exp (a,e') -> begin match a.a_cont with
                         | Aident i -> (* cas où a est juste un nom de
                                        * variable *)
                             begin try
                               let t1 = var_lookup i env in
                               (* on a bien trouvé la variable identifiée
                                * par i *)
                               let e'' = type_expr env tro e' in
                               if is_sstype env e'.e_loc e''.te_typ t1 then
                                 (* t1 est bien un sous type de t2 *)
                                 {
                                   te_cont = TEacc_exp
                                     ((tacces_of_acces a), e'');
                                   te_loc = e.e_loc;
                                   te_typ = Tunit
                                 }
                               else (* t1 n'est pas un sous type de t2 *)
                                 raise (TypeError (e.e_loc, "le type de
                                      \""^i^"\" n'est pas compatible avec celui
                                      de l'expression qu'on lui affecte")) 
                             with
                               | Not_found -> (* On a pas trouvé la
                                   variable i dans l'environnement, on
                                   cherche this.i *)
                                   type_expr env tro {
                                     e_cont = Eacc_exp ({
                                         a_cont = Aexpr_ident({
                                           e_cont = Ethis;
                                           e_loc = a.a_loc
                                         }, i);
                                         a_loc = a.a_loc
                                       }, e');
                                     e_loc = e'.e_loc        
                                   }
                             end
                         | Aexpr_ident (e'', i) -> (* On type récursivement
                                                    * e''.i dans e''.i = e' *)
                             let e1 = type_expr env tro {
                                 e_cont = Eacc {
                                     a_cont = Aexpr_ident (e'',i);
                                     a_loc = a.a_loc
                                   };
                                 e_loc = a.a_loc
                             } in
                             let e2 = type_expr env tro e' in
                             if is_sstype env e'.e_loc e2.te_typ e1.te_typ then
                               let a' = begin match e1.te_cont with
                                 | TEacc a'' -> a''
                                 | _         -> failwith "Comment on a fait
                                                pour en arriver là ?"
                               end in {
                                   te_cont = TEacc_exp (a', e2);
                                   te_loc = e.e_loc;
                                   te_typ = Tunit
                                 }
                             else
                               raise (TypeError (e.e_loc,"Le type de
                               la variable \""^i^"\" est incompatible avec le
                               type de l'expression qu'on lui affecte"))
                       end
  (* -e' est un entier si e' est un entier, erreur sinon *)
  | Emoins e' ->  let e'' = type_expr env tro e' in
                  begin match e''.te_typ with
                    | Tint -> {
                          te_cont = TEmoins e'';
                          te_loc = e'.e_loc;
                          te_typ = Tint
                        } 
                    | _ ->  raise (TypeError (e'.e_loc, "Cette
                            expression n'est pas entière, on ne peut pas
                            prendre son opposé"))
                  end
  (* !e' est un booléen si e' est un booléen, erreur sinon *)
  | Eneg e' ->  let e'' = type_expr env tro e' in
                begin match e''.te_typ with
                  | Tboolean -> {
                        te_cont = TEneg e'';
                        te_loc = e'.e_loc;
                        te_typ = Tboolean
                      }
                  | _ ->  raise (TypeError (e'.e_loc, "Cette
                          expression n'est pas booléenne, on ne peut pas la
                          nier"))
                end
  | Ebinop (b, e1, e2) -> 
                (* On type d'abord les deux opérandes de l'opération binaire *)
                let e1' = type_expr env tro e1 in
                let e2' = type_expr env tro e2 in
                begin match b.b_cont with
                  (* On peut comparer les classes et les chaînes de caractères
                   * avec ne et eq (chez nous : NeRef et EqRef)
                   * Le résultat est un booléen *)
                  | NeRef | EqRef -> 
                      if (is_sstype env e1'.te_loc e1'.te_typ TanyRef) &&
                         (is_sstype env e2'.te_loc e2'.te_typ TanyRef) then {
                              te_cont = TEbinop ((tbinop_of_binop b),e1',e2');
                              te_loc = e.e_loc;
                              te_typ = Tboolean
                            }
                      else raise (TypeError (b.b_loc, "Cette
                        opération n'est permise que sur les
                        classes héritant de AnyRef"))
                  (* On peut comparer les entiers avec ==, =!, <, >, <=, >=
                   * Le résultat est un booléen *)
                  | Eq | Ne | Lt | Le | Gt | Ge ->
                      if (e1'.te_typ = Tint) && (e2'.te_typ =  Tint) then {
                          te_cont = TEbinop ((tbinop_of_binop b), e1', e2');
                          te_loc = e.e_loc;
                          te_typ = Tboolean
                        }
                      else raise (TypeError (b.b_loc, "Impossible de comparer
                           des expressions non entières"))
                  (* Le calcul booléen avec && et || *)
                  | And | Or ->
                      if (e1'.te_typ = Tboolean) && (e2'.te_typ = Tboolean)
                      then {
                          te_cont = TEbinop ((tbinop_of_binop b), e1', e2');
                          te_loc = e.e_loc;
                          te_typ = Tboolean
                        }
                      else raise (TypeError (b.b_loc, "Impossible d'effectuer
                           une opération booléenne sur des expressions non
                           booléennes"))
                  (* Les opérations arithmétiques avec +, -, *, /, % *)
                  | Add | Sub | Mul | Div | Mod ->
                      if (e1'.te_typ = Tint) && (e2'.te_typ = Tint) then {
                          te_cont = TEbinop ((tbinop_of_binop b), e1', e2');
                          te_loc = e.e_loc;
                          te_typ = Tint
                        }
                      else raise (TypeError (b.b_loc, "Une des deux
                           opérandes n'est pas un entier"))
                end
  | Eprint e' ->let e'' = type_expr env tro e' in
                (* On type d'abord e' et on autorise le print si c'est un entier
                 * ou un chaîne de caractères
                 * Cette opération est de type unit *)
                begin match e''.te_typ with
                  | Tint -> {
                        te_cont = TEprint e'';
                        te_typ = Tunit;
                        te_loc = e.e_loc
                      }
                  | Tstring -> {
                        te_cont = TEprint e'';
                        te_typ = Tunit;
                        te_loc = e.e_loc
                      }
                  | _ -> raise (TypeError (e'.e_loc, "Cette
                         expression n'est pas imprimable"))
                end
  (* Structure if (eb) e1 else e2 *)
  | Eifelse (eb, e1, e2) ->
                (* On type eb, e1, e2 *)
                let eb' = type_expr env tro eb in
                let e1' = type_expr env tro e1 in
                let e2' = type_expr env tro e2 in
                (* eb' doit être un booléen
                 * Les types de e1' et e2' doivent être comparables *)
                if (eb'.te_typ = Tboolean) &&
                   ((is_sstype env e.e_loc e1'.te_typ e2'.te_typ) ||
                   (is_sstype env e.e_loc e2'.te_typ e1'.te_typ))
                then {
                      te_cont = TEifelse (eb', e1', e2');
                      te_typ = max_type env e1'.te_typ e2'.te_typ e.e_loc;
                      te_loc = e.e_loc
                    }
                else raise (TypeError (e.e_loc, "Le type de retour est mal 
                     défini : les cas if et else ont des types
                     incompatibles"))
  (* Le sucre syntaxique : 
   * On se ramène au cas précédent avec un () pour le deuxième argument
   * (Evoid chez nous) *)
  | Eif(eb, e1) ->
                type_expr env tro {
                  e_cont = Eifelse (eb,e1,{e_cont = Evoid; e_loc = e.e_loc});
                  e_loc = e.e_loc
                }
  (* Boucle while (eb) e1 *)
  | Ewhile (eb, e1) ->    
                (* il suffit juste que eb soit booléenne et que e1 soit bien
                 * typée *)
                let eb' = type_expr env tro eb in
                if eb'.te_typ = Tboolean then
                  let e1' = type_expr env tro e1 in {
                    te_cont = TEwhile (eb', e1');
                    te_typ = Tunit;
                    te_loc = e.e_loc
                  }
                else raise (TypeError (eb.e_loc, "Cette expression n'est pas
                     booléenne"))
  | Enew (cid, argst , es) ->
                (* On récupère d'abord la classe concernée dans l'env *)
                let c = try classe_lookup env cid with
                  | Not_found -> raise (TypeError (e.e_loc, "L'identificateur
                  \""^cid^"\" ne fait référene à aucune classse connue."))
                (* On fabrique la substitution définie par argst *)
                in let targst = targst_of_argst env argst in
                let s = subst_from_lists
                  (List.map tpt_of_tptc c.cc_tptcs)
                  targst.tat_cont in 
                (* Vérifie que le type C[sigma = s] est bien formé *)
                begin match (is_bf env e.e_loc (Tclasse (cid, s))) with
                  | Some eloc -> raise (TypeError (eloc, "Ce type classe n'est
                      pas bien formé"))
                  | None  -> ()
                end;
                (* On type les expressions qui définissent l'objet *)
                let es' = List.map (type_expr env tro) es in
                (* On verifie que le sous typage est bon.
                  * On garde la localisation de l'erreur lorsque ce n'est pas
                  * le cas.
                  * On vérifie au passage que l'utilsateur a fourni le bon
                  * nombre d'arguments : fold_left2 soulève une erreur si ce
                  * n'est pas le cas.
                  * D'où une fonction de test un peu longue... *)
                let (welltyped, errloc_o) = begin try (List.fold_left2 (fun (b,o) e' p -> 
                      begin match o with
                        | None ->
                            let b' = is_sstype env e'.te_loc e'.te_typ
                                  (subst env s p.tp_typ) in
                            (b && b', if b' then None else Some e'.te_loc)
                        | Some errloc -> (false, Some errloc)  
                      end) (true, None) es' c.cc_params)
                with
                  | Invalid_argument _ -> raise (TypeError (e.e_loc, "Ce
                                          constructeur de classe n'est pas
                                          appelé avec le bon nombre
                                          d'arguments"))
                end in
                if welltyped then (* On peut enfin typer le new *)
                  {
                    te_cont = TEnew (cid, targst, es');
                    te_typ = Tclasse (cid, s);
                    te_loc = e.e_loc
                  }
                else begin
                  match errloc_o with
                    | None ->        failwith "On ne peut pas recevoir None ici"
                    | Some errloc -> raise (TypeError (errloc, "Le type de
                                      cette expression est incompatible avec
                                      la classe"))
                end
  | Eacc_typ_exp (a, argst, es) ->
                begin match a.a_cont with
                  | Aident m ->
                      (* Le sucre syntaxique : m tout seul signifie this.x
                       * On s'en sort avec un appel récursif sur l'autre cas *) 
                      type_expr env tro {
                        e_cont = Eacc_typ_exp ({
                          a_cont = Aexpr_ident ({
                            e_cont = Ethis;
                            e_loc = a.a_loc
                          }, m);
                          a_loc = a.a_loc
                          }, argst, es);
                        e_loc = e.e_loc
                      }
                  | Aexpr_ident (e', m_id) ->
                      (* On commence par typer l'expression qui appelle la
                       * méthode et on vérifie que c'est une instance de classe *) 
                      let e'' = type_expr env tro e' in
                      let (cid,s) = begin match e''.te_typ with
                        | Tclasse(cid, s) -> (cid,s)
                        | _ -> raise (TypeError (a.a_loc, "Cette expression
                               n'est pas une instance d'une classe, elle ne
                               peut pas avoir de méthode"))
                      end in
                      let c = classe_lookup env cid in
                      (* On va chercher la méthode dans l'environnement. *)
                      let m = begin try meth_lookup m_id c.cc_env  with
                        (* Si la méthode a été typée récemment, elle n'est pas
                         * encore dansc.cc_env mais elle est dans env *)
                        | Not_found ->
                            begin try
                              meth_lookup m_id env
                            with
                              | Not_found ->
                                  raise (TypeError (a.a_loc, "L'identifiant
                                  \""^m_id^"\" ne fait référence à aucune
                                  méthode connue."))
                            end
                      end in
                      (* On calcule les types donnés en argument et on stocke
                       * leur localisation au passage *)
                      let loctyps = List.map
                              (fun t -> (typerType_of_typ env t, t.t_loc))
                              (get_list argst.at_cont)
                      in let (taus, _) =  List.split loctyps in
                      (* On vérifie que types calculés dans loctyps sont bien
                       * formés *)
                      begin match (List.fold_left (fun errloc_o (t, tloc) ->
                                    begin match errloc_o with
                                      | None -> is_bf env argst.at_loc t
                                      | Some errloc as o -> o
                                    end ) None loctyps) with 
                        | Some errloc -> raise (TypeError (errloc, "Ce
                                          type n'est pas bien formé."))
                        | None -> ()
                      end;
                      (* On calcule la substitution associée à la méthode et on
                       * vérifie que sa composée avec la substitution qui
                       * définit la classe est bien formée. *)
                      let s' = subst_from_lists m.tm_type_params taus in
                      let all_tpts = m.tm_type_params @
                          (List.map tpt_of_tptc c.cc_tptcs) in
                      let ss' = subst_compose s s' in
                      begin match is_subst_bf env all_tpts ss' with
                        | Some eloc -> raise (TypeError (eloc, "Cette
                            substitution n'est pas bien formée, le problème ce
                            situe au niveau du type localisé"))
                        | None      -> ()
                      end;
                      (* On type toutes les expressions passées en paramètre de
                       * la méthode. *)
                      let es' = List.map (type_expr env tro) es in
                      (* On extrait la liste des types des arguments de la
                       * méthode dans sa définition. *)
                      let tau's = List.map (fun p -> p.tp_typ) m.tm_params in
                      (* On vérifie que les types calculés sont bien supérieurs
                       * aux types annoncés par le programme *)
                      begin try 
                        iter3 (fun t1 t2 eloc ->
                            if is_sstype env e.e_loc t1 t2 then
                                ()
                            else 
                                raise (TypeError (eloc, "Les types sont
                                incompatibles")))
                            (List.map (fun exp -> exp.te_typ) es')
                            (List.map (subst env ss') tau's) 
                            (List.map (fun exp -> exp.te_loc) es')
                      with
                        | Invalid_argument _ -> raise (TypeError
                        (e.e_loc, "Cette méthode n'a pas reçu le bon
                        nombre d'arguments."))
                      end;


                      (* On type enfin l'application de la méthode. *)
                      {
                        te_cont = TEacc_typ_exp ({
                          ta_cont = TAexpr_ident(e'', m_id);
                          ta_loc  = a.a_loc
                        }, targst_of_argst env argst, es');
                        te_typ = subst env ss' m.tm_res_type; 
                        te_loc = e.e_loc
                      }
                end

                      
  | Ereturn None -> if is_sstype env e.e_loc Tunit (match tro with
                              | None -> failwith "On a oublié de mettre le type
                                  de retour de la méthode qu'on type dans tro"
                              | Some tr -> tr) then
                      {
                        te_cont = TEreturn None;
                        te_typ = Tnothing;
                        te_loc = e.e_loc
                      }
                    else
                      raise (TypeError (e.e_loc, "Soit il manque un argument à
                      return soit le type de retour de cette méthode est mal
                      spécifié"))
  | Ereturn (Some e') -> let tr = begin match tro with | None -> failwith "On a
                         oublié de préciser le type de retour de la méthode
                         qu'on type" | Some tr -> tr end in
                         let e'' = type_expr env tro e' in
                         if is_sstype env e''.te_loc e''.te_typ tr then
                           {
                             te_cont = TEreturn (Some e'');
                             te_typ = Tnothing;
                             te_loc = e.e_loc
                           }
                         else
                             raise (TypeError (e.e_loc, "Le type de la valeur
                             renvoyée n'est pas compatible avec le type de
                             retour de la méthode "))
  | Ebloc b ->  match b.bl_cont with
                | []    -> {
                             te_cont = TEbloc [];
                             te_typ = Tunit;
                             te_loc = e.e_loc
                           }
                | [Iexpr e']  -> let e'' = type_expr env tro e' in
                           {
                             te_cont = TEbloc [ TIexpr e'' ];
                             te_typ  = e''.te_typ;
                             te_loc = e.e_loc
                           }
                | ins::q -> 
                            let q' =  { e_cont = Ebloc { 
                                        bl_cont  = q ;
                                        bl_loc = b.bl_loc
                                        };
                                        e_loc = e.e_loc
                                    } in
                            begin match ins with
                              | Ivar v      -> 
                                  let (env', tv) = type_var tro env v in
                                  let eb = type_expr env' tro q' in
                                  let b' = begin match eb.te_cont with
                                    | TEbloc bl -> bl 
                                    | _         -> failwith "cette variable ne pas
                                                  être autre chose qu'un
                                                  bloc."
                                  end in 
                                  {
                                    te_cont = TEbloc ( (TIvar tv) :: b');
                                    te_typ = eb.te_typ;
                                    te_loc = e.e_loc 
                                  }
                              | Iexpr  e'    -> 
                                  let eb = type_expr env tro q' in
                                  let b' = begin match eb.te_cont with
                                  | TEbloc bl -> bl 
                                  | _         -> failwith "cette variable ne pas
                                                  être autre chose qu'un bloc"
                                  end in      
                                  let e'' = type_expr env tro e' in
                                      {
                                          te_cont = (TEbloc ((TIexpr e'') :: b'));
                                          te_typ  = eb.te_typ ;
                                          te_loc  = e.e_loc
                                      }
                            end

(* typerType option -> env -> var -> (env * tvar) *
 * Type la variable en faisant tous les tests de sous typage et de bien
 * formation puis renvoie la variable typée et un environnement enrichi de cette
 * nouvelle variable. *)
and type_var tro env v =
  (* Là on distingue en fonction de si l'utilisateur a spécifié un type ou
   * non. On garde aussi un booléen idiquant si la variable est un val ou
   * un var. Ça nous évite d'écrire deux fois le même code par la suite.*)
  let (x, t_o, ev, isval) =  begin match v.v_cont with
    | Val (x, t_o, ev) -> (x, t_o, ev, true)
    | Var (x, t_o, ev) -> (x, t_o, ev, false)
  end in
  (* On type ev. *)
  let ev' = type_expr env tro ev in
  begin match t_o with 
    | None   -> 
        (* On type la variable et on crée l'environnement étendu. *)
        let tv = 
            {
              tv_cont = (if isval then 
                  TVal (x, ev'.te_typ, ev')
              else
                  TVar (x, ev'.te_typ, ev')
              );
              tv_typ = ev'.te_typ;
              tv_loc = v.v_loc
            } in
        (add_tvar_env env tv, tv)
    | Some user_t ->
        (* On vérifie que le type fourni par le programme est bien formé. *)
        let t = begin try 
          typerType_of_typ env user_t
        with
          | Not_found -> failwith "typerType_of_typ a échoué dans type_var"
        end in
        begin match is_bf env user_t.t_loc t with
          | None -> ()
          | Some eloc ->
              raise (TypeError (eloc, "Ce type n'est pas bien formé."))
        end;
        (* On vérifie si le type fourni par l'utilisateur est bien compatible
         * avec le type calculé. *)
        if is_sstype env ev'.te_loc ev'.te_typ t then
          ()
        else
          raise (TypeError (user_t.t_loc, "Le type spécifié est incompatible 
          avec l'expression qui suit."));
        (* On renvoie le résultat : l'environnement augmenté et la variable
         * typée. *)
        let tv = 
            {
              tv_cont = (if isval then 
                  TVal (x, t, ev')
              else
                  TVar (x, t, ev')
              );
              tv_typ = ev'.te_typ;
              tv_loc = v.v_loc
            } in
        (add_tvar_env env tv, tv) 
  end 


(* context -> param_type -> context *)
let pt_add env pt =
  let env' = add_classe_env env {
    cc_name   = get_pt_id pt;
    cc_tptcs  = [];
    cc_params = [];
    cc_deriv  = begin match snd pt.pt_cont with
        | None          -> None 
        | Some (Hinf t) -> None 
        | Some (Hsup t) -> Some (typerType_of_typ env t, [])
    end ;
    cc_env = env (* whatev's *)
  } in begin match snd pt.pt_cont with
    | Some (Hinf t) -> add_constr_env env' (fst pt.pt_cont, typerType_of_typ env' t)
    | _             -> env'    
  end

(* Vérifie si un paramètre est bien formé dans l'environnement env renvoie un
 * environnement étendu avec de paramètre comme val.
 * context -> parametre -> context *)
let check_param env p =
  let p_type = typerType_of_typ env p.p_typ in
  match is_bf env p.p_loc p_type with
    | None ->
        add_var_env env (CVal (p.p_name, p_type))
    | Some eloc ->
        raise (TypeError (eloc, "Le type de ce paramètre n'est pas bien formé.")) 

(* param_type -> tparam_type *)
let tpt_of_pt env pt = 
  let tptcont = begin match pt.pt_cont with
    | (i, Some (Hinf t))  -> (i, Some (HTinf (typerType_of_typ env t)))
    | (i, Some (Hsup t))  -> (i, Some (HTsup (typerType_of_typ env t)))
    | (i, None)           -> (i, None )
  end in
  { 
    tpt_cont = tptcont;
    tpt_loc = pt.pt_loc
  }

(* context -> param -> tparam *)
let tparam_of_param env p =
  {
    tp_name = p.p_name;
    tp_typ  = typerType_of_typ env p.p_typ;
    tp_loc   = p.p_loc
  }

(* Vérifie l'alpha équivalence des types des paramètres de deux méthodes.
 * tmethode -> tmethode -> Cset.t *) 
(* FIXME : incomplet *)
let alpha_eq m1 m2 = 
  let rec f cset ts1 ts2 = match (ts1, ts2) with
    | ([], [])          -> cset
    | (t1::q1, t2::q2)  ->
        begin match (t1, t2) with
          (* Pour les types classe, il faut d'abord vérifier si se sont des
           * paramètres de type de la méthode ou non. *)
          | Tclasse (cid1, s1), Tclasse (cid2, s2) ->
              let tpts1 = List. filter (fun tpt -> get_tpt_id tpt = cid1)
              m1.tm_type_params in
              if List.length tpts1 = 1 then begin
                (* cid1 est un paramètre de type. *)
                let tpts2 = List.filter (fun tpt -> get_tpt_id tpt = cid2)
                m2.tm_type_params in
                if List.length tpts2 <> 1 then
                  raise (TypeError (m1.tm_loc, "L'identifiant "^cid2^" devrait
                  faire référence à un paramètre de type de "^m2.tm_name^" dans
                  la classe dont on hérite. La méthode ne peut pas être
                  surchargée."));
                (* cid2 est aussi un paramètre de type. *)
                let cor = ref None in
                Cset.iter (fun c -> if fst c = cid1 then cor := (Some c)) cset;
                match !cor with
                  | None ->
                      (* Si il existe déjà une correspondance entre un
                       * identifiant et cid2, on soulève une erreur, il n'y a
                       * pas alpha-équivalence. *)
                      if Cset.exists (fun cpl -> snd cpl = cid2) cset then
                        raise (TypeError (m1.tm_loc, "Impossible de surcharger
                        la méthode "^m1.tm_name^", les types des paramètres sont
                        incompatibles."));
                      (* On vérifie que les bornes éventuelles de ces deux
                       * paramètres de type sont équivalentes. *)
                      let bornes_ok = begin
                        let b1 = snd (List.hd tpts1).tpt_cont in
                        let b2 = snd (List.hd tpts2).tpt_cont in
                        match (b1, b2) with
                          | (None, None) -> true
                          | (Some (HTinf tb1), (Some (HTinf tb2))) ->
                              ignore (f cset [tb1] [tb2]);
                              true
                          | (Some (HTsup tb1), (Some (HTsup tb2))) ->
                              ignore (f cset [tb1] [tb2]);
                              true
                          | _ -> false 
                      end in
                      if not bornes_ok then 
                        raise (TypeError (m1.tm_loc, "Impossible de surcharger
                        la méthode "^m1.tm_name^", les types des paramètres sont
                        incompatibles."));
                      f (Cset.add (cid1, cid2) cset) q1 q2  
                  | Some (id1, id2) ->
                      if id2 <> cid2 then
                        raise (TypeError (m1.tm_loc, "Impossible de surcharger
                        la méthode "^m1.tm_name^", les paramètres de types ne
                        sont pas identiques."))
                      else
                        f cset q1 q2
              end else if cid1 = cid2 then begin
                (* cid1/cid2 est une vraie classe. *)
                let sorting c1 c2 = Pervasives.compare c1 c2 in
                let (_, imgs1) =
                  List.split (List.sort sorting (Smap.bindings s1)) in
                let (_, imgs2) =
                  List.split (List.sort sorting (Smap.bindings s2)) in
                let cset' = f cset imgs1 imgs2 in
                f cset' q1 q2 
              end else
                raise (TypeError (m1.tm_loc, "Les classes "^cid1^" et "^cid2^"
                sont différentes, la méthode "^m1.tm_name^" ne peut pas être
                surchargée."))
          (* Pour les types builtin, il suffit de tester leur égalité. *)
          | t1, t2 ->
              if t1 = t2 then
                f cset q1 q2
              else
                (* Pour ce print pas besoin d'environnement donc on donne
                 * l'environnement vide. *)
                let tn1 = string_of_typ (env0 ()) t1 in
                let tn2 = string_of_typ (env0 ()) t2 in
                raise (TypeError (m1.tm_loc, "Impossible de surcharger la
                méthode \""^m1.tm_name^"\" car les types "^tn1^" et "^tn2^" sont
                différents."))
        end
    | _ -> raise (TypeError (m1.tm_loc, "Impossible de surcharger la méthode
    \""^m1.tm_name^"\" car le nombre d'arguments fournis n'est pas le bon."))
  in
  let ts1 = List.map (fun tp -> tp.tp_typ) m1.tm_params in
  let ts2 = List.map (fun tp -> tp.tp_typ) m2.tm_params in
  f Cset.empty ts1 ts2
      
(* Cset.t -> typerType -> typerType *)
let rec alpha_subst cset = function
  | Tclasse (cid, s) ->
      let cset' = Cset.filter (fun c -> snd c = cid) cset in
      begin match Cset.cardinal cset' with
        | 0 ->
            let s' = Smap.map (alpha_subst cset) s in
            Tclasse (cid, s')
        | 1 ->
            let (id1, id2) = Cset.choose cset' in
            Tclasse (id1, s)
        | _ ->
            failwith "On ne doit pas avoir deux correspondances dans cset, il y
            a une erreur dans la fonction alpha_eq."
      end
  | t -> t

(* tmethode -> tmethode -> unit *)
let can_override env m1 m2 =
  (* D'abord, on vérifie qu'on n'est pas en train d'essayer de surcharger une
   * méthode définie dans le même bloc et non une méthode héritée. *)
  let (t1, t2) = try
    (var_lookup "this" m1.tm_env, var_lookup "this" m2.tm_env) 
  with
    | Not_found -> failwith "This doit figurer dans l'environnement des méthodes
                   à ce moment"
  in match (t1, t2) with
    | Tclasse (cid1, _), Tclasse (cid2, _) ->
        if cid1 = cid2 then
          raise (TypeError (m1.tm_loc, "Impossible de surcharger une méthode
          non héritée")) 
        else begin
          (* On vérifie l'alpha équivalence des types des paramètres et la
           * compatibilité des types de retour. *)
          let cset = alpha_eq m1 m2 in
          (* On substuitue dans le type de retour de m2 puis on vérifie le
           * sous-typage. *)
          let tr1 = m1.tm_res_type in
          let tr2 = alpha_subst cset m2.tm_res_type in
          print_endline (string_of_typ env tr1);
          print_endline (string_of_typ env tr2);
          if (is_sstype env m1.tm_loc tr1 tr2) then
            ()
          else
            raise (TypeError (m1.tm_loc, "Impossible de surcharger cette
            méthode, les types de retour sont incompatibles.")) 
        end
    | _, _ -> failwith "var_lookup est malade"

  

(* Typage des déclarations.
 * (context * tdecl list) -> decl -> (context * tdecl list) *)
let type_decl (env, tdl) d = match d.decl_cont with
  | Dvar v ->
      (* Unicité : on vérifie que le nom de la variable que l'on veut ajouter
       * n'est pas déjà pris. *)
      let v_id = begin match v.v_cont with
        | Var (i, _, _) -> i
        | Val (i, _, _) -> i
      end in 
      if  List.exists (fun cv -> get_cv_id cv = v_id) env.vars ||
          List.exists (fun tm -> tm.tm_name = v_id) env.meths then
        raise (TypeError (v.v_loc, "Le nom de variable "^v_id^" est déjà
        pris."));
      (* Pas de problème alor on type la méthode et on l'ajoute à
       * l'environnement. *)
      let env', tv = (type_var None env v) in
      (env', (TDvar tv)::tdl) 
  | Dmeth m ->
      (* On vérifie que les identificateurs des paramètres de type sont tous
      * différents. *)
      if not (list_uniq get_pt_id (get_meth_type_params m)) then
        raise (TypeError (m.m_loc, "Les paramètres de type de cette méthode
        ne sont pas distincts deux à deux."));
      (* On vérifie que les identificateurs des paramètres du constructeur sont
       * tous différents. *)
      if not (list_uniq (fun p -> p.p_name) (get_meth_params m)) then
        raise (TypeError (m.m_loc, "Les paramètres de cette méthode
        ne sont pas distincts deux à deux."));
      let gamma'' = ref env in
      (* On ajoute les paramètres de type comme des classes. *)
      gamma'' :=  List.fold_left pt_add !gamma'' (get_meth_type_params m);
      (* On vérifie que les types des argument sont bien formés et on ajoute les
       * arguments à l'environnement. *)
      gamma'' :=  List.fold_left check_param !gamma'' (get_meth_params m);
      (* On calcule le type de retour de la méthode *)
      let tau = begin match m.m_cont with
        | Mblock mb ->  Tunit
        | Mexpr me  ->  
            let tau = typerType_of_typ !gamma'' me.res_type
            in begin match is_bf !gamma'' m.m_loc tau with
                | Some eloc ->
                    raise (TypeError (eloc, "Ce type n'est pas bien formé à
                    l'endroit indiqué."))
                | None -> tau
            end
      end in
      (* On ajoute la méthode à gamma'' *)
      let tm = begin match m.m_cont with 
        | Mblock mb -> {
              tm_name = mb.mb_name;
              tm_override = mb.mb_override;
              tm_type_params = List.map (tpt_of_pt !gamma'')
                (get_list mb.mb_type_params);
              tm_params = List.map (tparam_of_param !gamma'') mb.mb_params;
              tm_res_type = tau;
              tm_res_expr = {te_cont = TEvoid; te_typ = tau; te_loc = m.m_loc};
              tm_loc = m.m_loc;
              tm_env = !gamma''
            }
        | Mexpr me  -> {
              tm_name = me.me_name;
              tm_override = me.me_override;
              tm_type_params = List.map (tpt_of_pt !gamma'')
                (get_list me.me_type_params);
              tm_params = List.map (tparam_of_param !gamma'') me.me_params;
              tm_res_type = tau;
              tm_res_expr = {te_cont = TEvoid; te_typ = tau; te_loc = m.m_loc};
              tm_loc = m.m_loc;
              tm_env = !gamma'' 
            }
      end in
      (* On ajoute cette version simplifié de la méthode à l'environnement local
       * de la méthode. Il n'a pas besoin d'en savoir plus. *)
      gamma'' := add_tmeth_env !gamma'' tm;
      (* On type l'expression qui définit la méthode *)
      let tm' = begin match m.m_cont with 
        | Mblock mb -> 
            let te = type_expr !gamma'' (Some tau) {
              e_cont = Ebloc mb.bloc;
              e_loc = mb.bloc.bl_loc
            } in {
              tm_name = mb.mb_name;
              tm_override = mb.mb_override;
              tm_type_params = List.map (tpt_of_pt !gamma'')
                (get_list mb.mb_type_params);
              tm_params = List.map (tparam_of_param !gamma'') mb.mb_params;
              tm_res_type = tau;
              tm_res_expr = te;
              tm_loc = m.m_loc;
              tm_env = !gamma''
            }
        | Mexpr me  ->
            let te = type_expr !gamma'' (Some tau) me.res_expr in {
              tm_name = me.me_name;
              tm_override = me.me_override;
              tm_type_params = List.map (tpt_of_pt !gamma'')
                (get_list me.me_type_params);
              tm_params = List.map (tparam_of_param !gamma'') me.me_params;
              tm_res_type = tau;
              tm_res_expr = te;
              tm_loc = m.m_loc;
              tm_env = !gamma''
            }
      end in
      (* On n'effectue qu'ici les tests liée au mot clef override *)
      if tm'.tm_override then
        let m' = begin try 
          meth_lookup tm'.tm_name env 
        with
          | Not_found ->  raise (TypeError (m.m_loc, "Cette méthode n'hérite
                          d'aucune classe existante"))
        end in
        can_override !gamma'' tm' m'; (* Unit si pas de problème, erreur sinon 
                              TODO : doit vérifier que "this" est différent dans
                              m et m' pour traiter le cas où on essaie de
                              surcharger une méthode du même bloc de
                              declaration. *)
      else
        if List.exists (fun cm -> cm.tm_name = tm'.tm_name) env.meths then
          raise (TypeError (m.m_loc, "Une méthode portant le même
          nom existe déjà"));
      (* On calcule enfin l'envirronement de retour. *)
      (add_tmeth_env env tm', (TDmeth tm')::tdl)  
      
(* context -> param_type_classe  -> context *)
let ptc_add env ptc = match get_ptc_borne ptc with
  | None -> add_classe_env env {
              cc_name   = get_ptc_id ptc;
              cc_tptcs  = [];
              cc_params = [];
              cc_deriv  = None;
              cc_env    = env (* On ne s'en sert jamais. *)
      }
  | Some (Hsup tau) ->
      let tau' = typerType_of_typ env tau in 
      begin match is_bf env tau.t_loc tau' with
        | None ->
            add_classe_env env {
                  cc_name   = get_ptc_id ptc;
                  cc_tptcs  = [];
                  cc_params = [];
                  cc_deriv  = Some (tau', []); (* en est-on bien sûr ... *)
                  cc_env    = env (* On ne s'en sert jamais. *)
            }
        | Some eloc -> raise (TypeError (eloc, "Le type de la borne est mal
            formé à l'endroit indiqué"))
      end
  | Some (Hinf tau) ->
      let tau' = typerType_of_typ env tau in 
      begin match is_bf env tau.t_loc tau' with
        | None ->
            add_constr_env (add_classe_env env {
                  cc_name   = get_ptc_id ptc;
                  cc_tptcs  = [];
                  cc_params = [];
                  cc_deriv  = None;
                  cc_env    = env (* On ne s'en sert jamais. *)
            }) (get_ptc_id ptc, tau')
        | Some eloc ->
            raise (TypeError (eloc, "La borne de ce parametre de type n'est
            pas bien formee à l'endroit indiqué."))
      end
      
  
(* env -> param_type_classe -> toparam_type_classe *)
let tptc_of_ptc env ptc = 
  let cont = match ptc.ptc_cont with
    | PTCplus  pt -> 
        TPTCplus {
          tpt_cont = begin match pt.pt_cont with
            | (i, None)           -> (i, None)
            | (i, Some (Hinf t))  -> (i, Some (HTinf (typerType_of_typ env t)))
            | (i, Some (Hsup t))  -> (i, Some (HTsup (typerType_of_typ env t)))
          end;
          tpt_loc = pt.pt_loc
        }
    | PTCmoins pt -> 
        TPTCmoins {
          tpt_cont = begin match pt.pt_cont with
            | (i, None)           -> (i, None)
            | (i, Some (Hinf t))  -> (i, Some (HTinf (typerType_of_typ env t)))
            | (i, Some (Hsup t))  -> (i, Some (HTsup (typerType_of_typ env t)))
          end;
          tpt_loc = pt.pt_loc
        }
    | PTCrien  pt -> 
        TPTCrien {
          tpt_cont = begin match pt.pt_cont with
            | (i, None)           -> (i, None)
            | (i, Some (Hinf t))  -> (i, Some (HTinf (typerType_of_typ env t)))
            | (i, Some (Hsup t))  -> (i, Some (HTsup (typerType_of_typ env t)))
          end;
          tpt_loc = pt.pt_loc
        }
  in
  {
    tptc_cont = cont;
    tptc_loc  = ptc.ptc_loc
  }

(* context -> parametre -> tparametre *)
let tparam_of_param env p = 
  {
    tp_name = p.p_name;
    tp_typ  = typerType_of_typ env p.p_typ;
    tp_loc = p.p_loc
  }  

(* typage des classes
 * context -> classe -> (context * tclasse) *) 
let type_classe env c =
  (* Unicité : on vérifie que la classe n'est pas déjà définie. *)
  begin try
    ignore (classe_lookup env c.c_name);
    raise (TypeError (c.c_loc, "On ne peut pas définir la classe "^c.c_name^",
    elle est déjà définie plus haut."))
  with
    | Not_found -> ()
  end;
  (* On vérifie que les identificateurs des paramètres de type sont tous
   * différents. *)
  if not (list_uniq get_ptc_id (get_list c.type_class_params)) then
    raise (TypeError (c.c_loc, "Les paramètres de type de cette classe ne sont
    pas distincts deux à deux."));
  (* On vérifie que les identificateurs des paramètres du consctructeur de la
   * classe sont tous différents. *)
  if not (list_uniq (fun p -> p.p_name) (get_list c.params)) then
    raise (TypeError (c.c_loc, "Les paramètres du constructeur de cette classe
    ne sont pas distincts deux à deux."));
  (* On declare des environnements mutables pour ne pas se perde *)
  let gamma  = ref env in
  let gamma' = ref env in
  (* 1. On checke les paramètre de type et on les ajoute à l'env *)
  gamma' := List.fold_left ptc_add !gamma' (get_list c.type_class_params);
  (* 2. On vérifie que le type dont on hérite est bien formé et on l'ajoute à
   * l'environnement. *)
  let (tptcs, tps, td) = begin match c.deriv with
    | None -> (
        List.map (tptc_of_ptc !gamma') (get_list c.type_class_params),
        List.map (tparam_of_param !gamma') (get_list c.params),
        None
      )
    | Some (t, es_o) ->
        let tau = typerType_of_typ !gamma' t in
        begin match is_bf !gamma' t.t_loc tau with
          | None ->
              begin match tau with
                | Tclasse (cid, _) ->
                    (* On va chercher dans l'environnement la classe dont on
                     * hérite. *)
                    let c' = begin try
                      classe_lookup env cid
                    with
                      | Not_found -> raise (TypeError (t.t_loc, "La classe
                      \""^cid^"\" n'existe pas."))
                    end in
                    (* On ajoute les méthodes et variables héritées à gamma' *)
                    gamma' := {
                      classes = !gamma'.classes;
                      constrs = !gamma'.constrs;
                      vars    = c'.cc_env.vars @ (!gamma'.vars);
                      meths   = c'.cc_env.meths @ (!gamma'.meths);
                      }
                (* Si on essaie d'hériter d'autre chose que d'une classe, on
                 * râle. *)
                | _ -> 
                    raise (TypeError (t.t_loc, "On ne peut pas hériter d'un type
                    builtin."))
              end
          (* le type dont on essaie d'hériter n'est pas bien formé. *)
          | Some eloc ->
              raise (TypeError (eloc, "Ce type n'est pas bien formé à l'endroit
              indiqué."));
        end;
        (
          List.map (tptc_of_ptc !gamma') (get_list c.type_class_params),
          List.map (tparam_of_param !gamma') (get_list c.params),
          Some (tau, List.map (type_expr !gamma' None) (get_list es_o))
        )
  end in
  (* la classe C avec seulement les champs hérités *)
  let tc0 = {
    cc_name   = c.c_name;
    cc_tptcs  = tptcs;
    cc_params = tps;
    cc_deriv  = td;
    cc_env = !gamma'
  } in 
  (* On ajoute ce C provisoire à gamma et gamma' aussi. *)
  gamma := add_classe_env !gamma tc0;
  gamma' := add_classe_env !gamma' tc0;
  (* 3. On vérifie que le type des parametres sont bien formés et on les ajoute
   * à l'envrionnement de la classe. *)
  gamma' := List.fold_left check_param !gamma' (get_list c.params);
  (* Et le this, on calcule la substitution une bonne fois pour toute ici. *)
  let newtyps = List.map
                  (fun ptc -> Tclasse (get_ptc_id ptc, subst0 ()))
                  (get_list c.type_class_params) in
  let s = subst_from_lists (List.map tpt_of_tptc tptcs) newtyps in
  gamma' := add_var_env !gamma' (CVal ("this", Tclasse (c.c_name, s)));
  (* 4. On vérifie que l'appel au constructeur de la super classe est légal.*)
  begin match c.deriv with
    (* Pas de test si pas d'héritage. *)
    | None            -> ()
    | Some (t, es_o)  ->
        let _ = type_expr !gamma' None
                  { e_cont = Enew(t.t_name, t.args_type, get_list es_o);
                    e_loc  = t.t_loc  
                  } in ()
  end;
  (* 5. On type la liste des déclarations.
   * On fait un pli avec la fonction type_decl définie plus haut sur la liste
   * des déclarations *) 
  let new_env, tdecls' = List.fold_left type_decl (!gamma', []) c.decls in
  gamma' := new_env;
  let tc = {
    tc_name             = c.c_name;
    ttype_class_params  = tptcs;
    tparams             = tps;
    tderiv              = td;
    tdecls              = tdecls';
    tc_loc              = c.c_loc;
    tc_env              = !gamma'
  } in let cc = context_classe_of_tclasse tc in
  (* Tests de variance *)
  variance_test_vars !gamma';
  variance_test_meths !gamma';
  (* On remplace le tc0 qu'on a mis tout à l'heure par le nouveau tc. *)
  gamma := {
    classes = replace_in_list
                (fun cl -> cl.cc_name = cc.cc_name)
                cc
                !gamma.classes;
    constrs = !gamma.constrs;
    vars    = !gamma.vars;
    meths   = !gamma.meths;
  };
  (!gamma, tc)
  
(* Typage de la classe Main
 * context -> classe_Main -> tclasse_Main *)  
let type_classe_Main env cm = 
  (* Fonction vérifiant qu'un méthode main est bien définie.
   * decl list -> (parametre list * ty) *)
  let rec find_main = function
    | [] ->
        raise (TypeError (cm.cM_loc, "La classe Main n'a pas de méthode
        \"main\"."))
    | d::q -> begin match d.decl_cont with
          | Dvar _  -> find_main q 
          | Dmeth m -> begin match m.m_cont with
              | Mblock mb ->
                  if mb.mb_name = "main" then
                    (mb.mb_params, {
                      t_name = "Unit";
                      args_type = {at_cont = None; at_loc = mb.bloc.bl_loc};
                      t_loc = mb.bloc.bl_loc})
                  else
                    find_main q
              | Mexpr me ->
                  if me.me_name = "main" then
                    (me.me_params, me.res_type)
                  else
                    find_main q
          end
    end in
  (* On vérifie que la méthode main trouéve est de la forme adéquate. *)
  let (ps, t) = find_main cm.cM_cont in begin match ps with
    | []  -> raise (TypeError (cm.cM_loc, "La méthode main doit avoit un
             paramètre possédant le type Array[String]."))
    | [p] -> 
        let right_args = begin match p.p_typ.args_type.at_cont with
          | None      ->  false
          | Some [t]  ->  t.t_name = "String" && t.args_type.at_cont = None
          | Some _    ->  false
        end in
        if (p.p_typ.t_name = "Array") && right_args then
          ()
        else
          raise (TypeError (cm.cM_loc, "La méthode main doit avoit un
          paramètre avec le type Array[String]."))
    | _   -> raise (TypeError (cm.cM_loc, "La méthode main doit avoit un
             paramètre avec le type Array[String].")) end;

  let _, tc = type_classe (add_classe_env env (array_tc (List.hd ps).p_loc)) {
    c_name = "Main";
    type_class_params = None;
    params = None;
    deriv = None;
    decls = cm.cM_cont;
    c_loc = cm.cM_loc
  } in
  {
    tcM_cont = tc.tdecls;
    tcM_loc  = tc.tc_loc;
    tcM_env  = tc.tc_env
  } 
    
let type_fichier f = 
  let (gamma, classes) = List.fold_left
      (fun (env, l) c -> let (e, tc) = type_classe env c in (e, tc::l))
      (env0 (), [])
      f.f_classes in
  let tcm = type_classe_Main gamma f.main in
  {
    tclasses = List.rev classes;
    tmain = tcm
  }


