import Base

# Equality theory for key comparison: the reflexivity tower Word -> U32 ->
# Char -> String, each level by induction over the previous. Every general
# merge/read law rewrites with string_eq_refl; it is the base of the
# soundness tower. Lemmas are closed proof-terms rewritten via `%`.
def word_cmp_refl(width: Nat, +word: Word(width)) -> {Word.cmp(width, word, word) == EQ{} : Cmp}:
  match width word:
    case 0n WNil{}:
      {==}
    case 1n+p WCon{ab, at}:
      match ab:
        case False{}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, word_cmp_refl(p, at)) : {Word.cmp.fin(False{}, False{}, _) == EQ{} : Cmp}
          {==}
        case True{}:
          %Equal.sym(Cmp, Word.cmp(p, at, at), EQ{}, word_cmp_refl(p, at)) : {Word.cmp.fin(True{}, True{}, _) == EQ{} : Cmp}
          {==}

# Lifts word reflexivity to 32-bit values.
def u32_cmp_refl(+value: U32) -> {U32.cmp(value, value) == EQ{} : Cmp}:
  match value:
    case U32{word_bits}:
      %Equal.sym(Cmp, Word.cmp(32n, word_bits, word_bits), EQ{}, word_cmp_refl(32n, word_bits)) : {_ == EQ{} : Cmp}
      {==}

# Lifts U32 reflexivity to characters.
def char_cmp_refl(+character: Char) -> {Char.cmp(character, character) == ((character, character), EQ{}) : (Char & Char) & Cmp}:
  match character:
    case Chr{code_bits}:
      %Equal.sym(Cmp, U32.cmp(code_bits, code_bits), EQ{}, u32_cmp_refl(code_bits)) : {((Chr{code_bits}, Chr{code_bits}), _) == ((Chr{code_bits}, Chr{code_bits}), EQ{}) : (Char & Char) & Cmp}
      {==}

# Lifts char reflexivity to strings, head then tail.
def string_cmp_pair_refl(+text: String) -> {String.cmp(text, text) == ((text, text), EQ{}) : (String & String) & Cmp}:
  match text:
    case SNil{}:
      {==}
    case SCon{head_char, tail_text}:
      %Equal.sym((Char & Char) & Cmp, Char.cmp(head_char, head_char), ((head_char, head_char), EQ{}), char_cmp_refl(head_char)) : {String.cmp.fin(tail_text, tail_text, _) == ((SCon{head_char, tail_text}, SCon{head_char, tail_text}), EQ{}) : (String & String) & Cmp}
      %Equal.sym((String & String) & Cmp, String.cmp(tail_text, tail_text), ((tail_text, tail_text), EQ{}), string_cmp_pair_refl(tail_text)) : {String.cmp.rec(head_char, head_char, _) == ((SCon{head_char, tail_text}, SCon{head_char, tail_text}), EQ{}) : (String & String) & Cmp}
      {==}

# String equality is reflexive: the top of the tower, used by every law.
def string_eq_refl(+text: String) -> {String.eq(text, text) == True{} : Bool}:
  match text:
    case SNil{}:
      {==}
    case SCon{head_char, tail_text}:
      %Equal.sym((Char & Char) & Cmp, Char.cmp(head_char, head_char), ((head_char, head_char), EQ{}), char_cmp_refl(head_char)) : {String.eq.fin(String.cmp.fin(tail_text, tail_text, _)) == True{} : Bool}
      %Equal.sym((String & String) & Cmp, String.cmp(tail_text, tail_text), ((tail_text, tail_text), EQ{}), string_cmp_pair_refl(tail_text)) : {String.eq.fin(String.cmp.rec(head_char, head_char, _)) == True{} : Bool}
      {==}
