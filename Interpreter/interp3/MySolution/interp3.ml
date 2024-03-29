#use "./../../../library/OCaml/MyOCaml.ml";;


type uopr =
  | Neg | Not

type bopr =
  | Add | Sub | Mul | Div | Mod
  | And | Or
  | Lt  | Gt  | Lte | Gte | Eq

type expr =
  | Int of int
  | Bool of bool
  | Unit
  | UOpr of uopr * expr
  | BOpr of bopr * expr * expr
  | Var of string
  | Fun of string * string * expr
  | App of expr * expr
  | Let of string * expr * expr
  | Seq of expr * expr
  | Ifte of expr * expr * expr
  | Trace of expr

(* ------------------------------------------------------------ *)

(* combinator for left-associative operators *)

let chain_left (p : 'a parser) (q : ('a -> 'a -> 'a) parser) : 'a parser =
  let* init = p in
  let* fms = many (let* f = q in let* m = p in pure (f, m)) in
  let m = list_foldleft fms init (fun acc (f, m) -> f acc m) in
  pure m

let rec chain_right (p : 'a parser) (q : ('a -> 'a -> 'a) parser) : 'a parser =
  let* m = p in
  (let* f = q in
   let* rest = chain_right p q in
   pure (f m rest)) <|> 
  (pure m)

let opt (p : 'a parser) : 'a option parser =
  (let* x = p in pure (Some x)) <|> pure None

(* basic constants *)

let parse_int : expr parser =
  let* n = natural in
  pure (Int n) << whitespaces

let parse_bool : expr parser =
  (keyword "true" >> pure (Bool true)) <|>
  (keyword "false" >> pure (Bool false))

let parse_unit : expr parser =
  keyword "(" >> keyword ")" >> pure Unit

(* names *)

let isReserved s =
  let reserved = 
    ["let"; "rec"; "in"; "fun"; "if"; "then"; "else"; "trace"; "mod"; "not"] 
  in
  list_exists reserved (fun s0 -> s0 = s)

let parse_name : string parser =
  let lower = satisfy char_islower in
  let upper = satisfy char_isupper in
  let digit = satisfy char_isdigit in
  let quote = char '\'' in
  let wildc = char '_' in
  let* c = lower <|> wildc in
  let* cs = many (lower <|> upper <|> digit <|> wildc <|> quote) in
  let s = string_make_fwork (list_foreach (c :: cs)) in
  if isReserved s then fail
  else pure s << whitespaces

(* unary operators *)

let parse_neg : (expr -> expr) parser =
  keyword "-" >> pure (fun m -> UOpr (Neg, m))

(* binary operators *)

let parse_add : (expr -> expr -> expr) parser =
  keyword "+" >> pure (fun m n -> BOpr (Add, m, n))

let parse_sub : (expr -> expr -> expr) parser =
  keyword "-" >> pure (fun m n -> BOpr (Sub, m, n))

let parse_mul : (expr -> expr -> expr) parser =
  keyword "*" >> pure (fun m n -> BOpr (Mul, m, n))

let parse_div : (expr -> expr -> expr) parser =
  keyword "/" >> pure (fun m n -> BOpr (Div, m, n))

let parse_mod : (expr -> expr -> expr) parser =
  keyword "mod" >> pure (fun m n -> BOpr (Mod, m, n))

let parse_and : (expr -> expr -> expr) parser =
  keyword "&&" >> pure (fun m n -> BOpr (And, m, n))

let parse_or : (expr -> expr -> expr) parser =
  keyword "||" >> pure (fun m n -> BOpr (Or, m, n))

let parse_lt : (expr -> expr -> expr) parser =
  keyword "<" >> pure (fun m n -> BOpr (Lt, m, n))

let parse_gt : (expr -> expr -> expr) parser =
  keyword ">" >> pure (fun m n -> BOpr (Gt, m, n))

let parse_lte : (expr -> expr -> expr) parser =
  keyword "<=" >> pure (fun m n -> BOpr (Lte, m, n))

let parse_gte : (expr -> expr -> expr) parser =
  keyword ">=" >> pure (fun m n -> BOpr (Gte, m, n))

let parse_eq : (expr -> expr -> expr) parser =
  keyword "=" >> pure (fun m n -> BOpr (Eq, m, n))

let parse_neq : (expr -> expr -> expr) parser =
  keyword "<>" >> pure (fun m n -> UOpr (Not, BOpr (Eq, m, n)))

let parse_seq : (expr -> expr -> expr) parser =
  keyword ";" >> pure (fun m n -> Seq (m, n))

(* expression parsing *)

let rec parse_expr () = 
  let* _ = pure () in
  parse_expr9 ()

and parse_expr1 () : expr parser = 
  let* _ = pure () in
  parse_int <|> 
  parse_bool <|> 
  parse_unit <|>
  parse_var () <|>
  parse_fun () <|>
  parse_letrec () <|>
  parse_let () <|>
  parse_ifte () <|>
  parse_trace () <|>
  parse_not () <|>
  (keyword "(" >> parse_expr () << keyword ")")

and parse_expr2 () : expr parser =
  let* m = parse_expr1 () in
  let* ms = many' parse_expr1 in
  let m = list_foldleft ms m (fun acc m -> App (acc, m)) in
  pure m

and parse_expr3 () : expr parser =
  let* f_opt = opt parse_neg in
  let* m = parse_expr2 () in
  match f_opt with
  | Some f -> pure (f m)
  | None -> pure m

and parse_expr4 () : expr parser =
  let opr = parse_mul <|> parse_div <|> parse_mod in
  chain_left (parse_expr3 ()) opr

and parse_expr5 () : expr parser =
  let opr = parse_add <|> parse_sub in
  chain_left (parse_expr4 ()) opr

and parse_expr6 () : expr parser =
  let opr = 
    parse_lte <|> 
    parse_gte <|>
    parse_neq <|>
    parse_lt <|> 
    parse_gt <|>
    parse_eq
  in
  chain_left (parse_expr5 ()) opr

and parse_expr7 () : expr parser =
  chain_left (parse_expr6 ()) parse_and

and parse_expr8 () : expr parser =
  chain_left (parse_expr7 ()) parse_or

and parse_expr9 () : expr parser =
  chain_right (parse_expr8 ()) parse_seq

and parse_var () : expr parser =
  let* x = parse_name in
  pure (Var x)

and parse_fun () : expr parser =
  let* _ = keyword "fun" in
  let* xs = many1 parse_name in 
  let* _ = keyword "->" in
  let* body = parse_expr () in
  let m = list_foldright xs body (fun x acc -> Fun ("", x, acc)) in
  pure m

and parse_let () : expr parser =
  let* _ = keyword "let" in
  let* x = parse_name in
  let* xs = many parse_name in
  let* _ = keyword "=" in
  let* body = parse_expr () in
  let* _ = keyword "in" in
  let* n = parse_expr () in
  let m = list_foldright xs body (fun x acc -> Fun ("", x, acc)) in
  pure (Let (x, m, n))

and parse_letrec () : expr parser =
  let* _ = keyword "let" in
  let* _ = keyword "rec" in
  let* f = parse_name in
  let* x = parse_name in
  let* xs = many parse_name in
  let* _ = keyword "=" in
  let* body = parse_expr () in
  let* _ = keyword "in" in
  let* n = parse_expr () in
  let m = list_foldright xs body (fun x acc -> Fun ("", x, acc)) in
  pure (Let (f, Fun (f, x, m), n))

and parse_ifte () : expr parser =
  let* _ = keyword "if" in
  let* m = parse_expr () in
  let* _ = keyword "then" in
  let* n1 = parse_expr () in
  let* _ = keyword "else" in
  let* n2 = parse_expr () in
  pure (Ifte (m, n1, n2))

and parse_trace () : expr parser =
  let* _ = keyword "trace" in
  let* m = parse_expr1 () in
  pure (Trace m) 

and parse_not () : expr parser =
  let* _ = keyword "not" in
  let* m = parse_expr1 () in
  pure (UOpr (Not, m))

exception SyntaxError
exception UnboundVariable of string

type scope = (string * string) list

let new_var =
  let stamp = ref 0 in
  fun x ->
    incr stamp;
    let xvar = string_filter x (fun c -> c <> '_' && c <> '\'') in
    string_concat_list ["v"; xvar; "i"; string_of_int !stamp]

let find_var scope s =
  let rec loop scope =
    match scope with
    | [] -> None
    | (s0, x) :: scope ->
      if s = s0 then Some x
      else loop scope
  in loop scope

let scope_expr (m : expr) : expr = 
  let rec aux scope m =
    match m with
    | Int i -> Int i
    | Bool b -> Bool b
    | Unit -> Unit
    | UOpr (opr, m) -> UOpr (opr, aux scope m)
    | BOpr (opr, m, n) -> 
      let m = aux scope m in
      let n = aux scope n in
      BOpr (opr, m, n)
    | Var s -> 
      (match find_var scope s with
       | None -> raise (UnboundVariable s)
       | Some x -> Var x)
    | Fun (f, x, m) -> 
      let fvar = new_var f in
      let xvar = new_var x in
      let m = aux ((f, fvar) :: (x, xvar) :: scope) m in
      Fun (fvar, xvar, m)
    | App (m, n) ->
      let m = aux scope m in
      let n = aux scope n in
      App (m, n)
    | Let (x, m, n) ->
      let xvar = new_var x in
      let m = aux scope m in
      let n = aux ((x, xvar) :: scope) n in
      Let (xvar, m, n)
    | Seq (m, n) ->
      let m = aux scope m in
      let n = aux scope n in
      Seq (m, n)
    | Ifte (m, n1, n2) ->
      let m = aux scope m in
      let n1 = aux scope n1 in
      let n2 = aux scope n2 in
      Ifte (m, n1, n2)
    | Trace m -> Trace (aux scope m)
  in
  aux [] m

(* ------------------------------------------------------------ *)

(* parser for the high-level language *)
let parse_prog (source_code: string): expr =
  match string_parse (whitespaces >> parse_expr ()) source_code with
  | Some (parsed_expr, []) -> scope_expr parsed_expr
  | _ -> raise SyntaxError

(* Concatenates two strings by interleaving their characters. *)
let concat_string (first: string) (second: string): string =
  let first_len = String.length first in
  let second_len = String.length second in
  let combined_len = first_len + second_len in
  String.init combined_len (fun index ->
    if index < first_len then first.[index]
    else second.[index - first_len]
  )

let rec compile_expr scope = function
  | Int i -> concat_string "Push " (concat_string (string_of_int i) "; ")
  | Bool b -> concat_string "Push " (concat_string (if b then "True" else "False") "; ")
  | Unit -> "Push Unit; "
  | UOpr (Neg, m) -> concat_string (compile_expr scope m) "Push -1; Mul; "
  | UOpr (Not, m) -> concat_string (compile_expr scope m) "Not; "
  | BOpr (Add, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Add; "
  | BOpr (Sub, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Sub; "
  | BOpr (Mul, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Mul; "
  | BOpr (Div, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Div; "
  | BOpr (Mod, m1, m2) -> compile_mod scope m1 m2
  | BOpr (And, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "And; "
  | BOpr (Or, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Or; "
  | BOpr (Lt, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Lt; "
  | BOpr (Gt, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Gt; "
  | BOpr (Lte, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Gt; Not; "
  | BOpr (Gte, m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Lt; Not; "
  | BOpr (Eq, m1, m2) -> compile_eq scope m1 m2
  | Var x ->
    (match find_var scope x with
      | None -> raise (UnboundVariable x)
      | Some v -> concat_string "Push " (concat_string v "; Lookup; "))
  | Fun (f, x, m) -> compile_fun scope f x m
  | App (m1, m2) -> concat_string (concat_string (compile_expr scope m1) (compile_expr scope m2)) "Swap; Call; "
  | Let (x, m1, m2) -> compile_let scope x m1 m2
  | Seq (m1, m2) -> concat_string (concat_string (compile_expr scope m1) "Pop; ") (compile_expr scope m2)
  | Ifte (m, n1, n2) -> compile_ifte scope m n1 n2
  | Trace m -> concat_string (compile_expr scope m) "Trace; "
  | _ -> failwith "Not implemented yet"

(* Compiles a modulo operation in the form (m1 mod m2). *)
and compile_mod scope m1 m2 =
  let cm1 = compile_expr scope m1 in
  let cm2 = compile_expr scope m2 in
  let divide = compile_expr scope (BOpr (Div, m1, m2)) in
  concat_string (concat_string divide (concat_string cm2 "Mul; ")) (concat_string cm1 "Sub; ")

(* Compiles an equality check in the form (m1 = m2). *)
and compile_eq scope m1 m2 =
  let less_than = compile_expr scope (BOpr (Lt, m1, m2)) in
  let great_than = compile_expr scope (BOpr (Gt, m1, m2)) in
  concat_string (concat_string less_than "Not; ") (concat_string great_than "Not; And; ")

(* Compiles a function definition with parameters and body. *)
and compile_fun scope f x m =
  let fv = new_var f in
  let f_scope = (f, fv) :: scope in
  let xv = new_var x in
  let x_f_scope = (x, xv) :: f_scope in
  let body = compile_expr x_f_scope m in
  concat_string
    (concat_string (concat_string "Push " (concat_string fv "; Fun "))
                   (concat_string "Push " (concat_string xv "; Bind; ")))
    (concat_string body "Swap; Return; End; ")

(* Compiles a let-binding expression. *)
and compile_let scope x m n =
  let cm = compile_expr scope m in
  let xv = new_var x in
  let x_scope = (x, xv) :: scope in
  let cn = compile_expr x_scope n in
  concat_string (concat_string cm (concat_string "Push " (concat_string xv "; ")))
                (concat_string "Bind; " cn)

(* Compiles an if-then-else expression. *)
and compile_ifte scope m n1 n2 =
  let _if = compile_expr scope m in
  let _then = compile_expr scope n1 in
  let _else = compile_expr scope n2 in
  concat_string (concat_string _if "If ")
                (concat_string _then (concat_string "Else " (concat_string _else "End; ")))

let compile (s : string) : string = (* YOUR CODE *)
  compile_expr [] (scope_expr (parse_prog s))
