import Base
import ../ber.bend as Ber
import ../src/Store.bend as Store
import ../src/Value.bend as Value
import ../src/Merging.bend as Merging

# IO harness: faithful certificates verify, tampered/empty/unknown ones fail.


def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def tampered_certificate(+valid_certificate: Merging.MergeCertificate) -> Merging.MergeCertificate:
  Merging.Make{Merging.cert_first_parent(valid_certificate), Merging.cert_second_parent(valid_certificate), Merging.cert_base_commit(valid_certificate), "0000tampered", Merging.cert_strategy_name(valid_certificate), Merging.cert_checked_laws(valid_certificate)}

def verify_both_certificates(+valid_certificate: Merging.MergeCertificate) -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    valid_outcome : Bool <- Ber.verify_certificate(valid_certificate)
    tampered_outcome : Bool <- Ber.verify_certificate(tampered_certificate(valid_certificate))
    return Con{flag_text("verify-valid-accepts", valid_outcome), Con{flag_text("verify-tampered-rejects", Bool.not(tampered_outcome)), Nil{}}}

def review_merge_certificate(cert_maybe: Maybe<&2, Merging.MergeCertificate>) -> Store.Op<&2, List<&2, String>>:
  match cert_maybe:
    case None{}:
      do Store.Op<&2, List<&2, String>>:
        return Con{"merge-produced-cert: FAIL", Nil{}}
    case Some{valid_certificate}:
      verify_both_certificates(valid_certificate)

def scenario_outcome() -> Store.Op<&2, List<&2, String>>:
  do Store.Op<&2, List<&2, String>>:
    +base_identifier : String <- Ber.commit_value("session_first", "ledger", "record_base", Value.Text{"base_version"}, Nil{})
    +first_identifier : String <- Ber.commit_value("session_first", "ledger", "record_alpha", Value.Text{"alpha_version"}, Con{base_identifier, Nil{}})
    +second_identifier : String <- Ber.commit_value("session_first", "ledger", "record_beta", Value.Text{"beta_version"}, Con{base_identifier, Nil{}})
    merge_outcome : Merging.MergeResult <- Ber.merge_commits(first_identifier, second_identifier, "union-disjoint")
    review_flags : List<&2, String> <- review_merge_certificate(Merging.success_certificate_of(merge_outcome))
    return review_flags

def join_lines(text_lines: List<&2, String>) -> String:
  match text_lines:
    case Nil{}:
      ""
    case Con{head_text, remaining_texts}:
      head_text ++ "\n" ++ join_lines(remaining_texts)

def print_scenario_result(result_pair: Store.Handle & List<&2, String>) -> IO(Unit):
  match result_pair:
    case (unused_store, text_lines):
      IO.print(join_lines(text_lines))

def main() -> IO(Unit):
  opened_store : Store.Handle = Store.open_store("certificate-check")
  print_scenario_result(Store.run_op(&2, List<&2, String>, opened_store, scenario_outcome()))
