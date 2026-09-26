import Base
import ../src/Staging.bend as Staging
import ../src/History.bend as History
import ../src/Merging.bend as Merging
import ../src/Certificate.bend as Certificate
import ../src/LogicalKey.bend as LogicalKey
import mylsm-lsm-store@0.3.1.0/mylsm.bend as MyLsmStore
import mylsm-lsm-store@0.3.1.0/src/Db.bend as DbTypes

def flag_text(check_name: String, condition: Bool) -> String:
  match condition:
    case True{}:
      check_name ++ ": PASS"
    case False{}:
      check_name ++ ": FAIL"

def tampered_certificate(+valid_certificate: Merging.MergeCertificate) -> Merging.MergeCertificate:
  Merging.Make{Merging.cert_first_parent(valid_certificate), Merging.cert_second_parent(valid_certificate), Merging.cert_base_commit(valid_certificate), "0000tampered", Merging.cert_strategy_name(valid_certificate), Merging.cert_checked_laws(valid_certificate)}

def verify_both_certificates(+valid_certificate: Merging.MergeCertificate) -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    valid_outcome : Bool <- Certificate.verify_certificate(valid_certificate)
    tampered_outcome : Bool <- Certificate.verify_certificate(tampered_certificate(valid_certificate))
    return Con{flag_text("verify-valid-accepts", valid_outcome), Con{flag_text("verify-tampered-rejects", Bool.not(tampered_outcome)), Nil{}}}

def review_merge_certificate(cert_maybe: Maybe<&2, Merging.MergeCertificate>) -> MyLsmStore.Sess<&2, List<&2, String>>:
  match cert_maybe:
    case None{}:
      do MyLsmStore.Sess<&2, List<&2, String>>:
        return Con{"merge-produced-cert: FAIL", Nil{}}
    case Some{valid_certificate}:
      verify_both_certificates(valid_certificate)

def scenario_outcome() -> MyLsmStore.Sess<&2, List<&2, String>>:
  do MyLsmStore.Sess<&2, List<&2, String>>:
    staged_base : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_base", "base_version")
    base_commit : History.Commit <- History.create_commit("session_first", Nil{}, Nil{})
    +base_identifier : String = History.commit_identifier_of(base_commit)
    staged_branch_first : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_alpha", "alpha_version")
    first_branch : History.Commit <- History.create_commit("session_first", Con{base_identifier, Nil{}}, Nil{})
    +first_identifier : String = History.commit_identifier_of(first_branch)
    staged_branch_second : LogicalKey.LogicalKey <- Staging.put_record("session_first", "ledger", "record_beta", "beta_version")
    second_branch : History.Commit <- History.create_commit("session_first", Con{base_identifier, Nil{}}, Nil{})
    +second_identifier : String = History.commit_identifier_of(second_branch)
    merge_outcome : Merging.MergeResult <- Merging.merge_commits(first_identifier, second_identifier, "union-disjoint")
    review_flags : List<&2, String> <- review_merge_certificate(Merging.success_certificate_of(merge_outcome))
    return review_flags

def join_lines(text_lines: List<&2, String>) -> String:
  match text_lines:
    case Nil{}:
      ""
    case Con{head_text, remaining_texts}:
      head_text ++ "\n" ++ join_lines(remaining_texts)

def print_scenario_result(result_pair: DbTypes.Db & List<&2, String>) -> IO(Unit):
  match result_pair:
    case (unused_store, text_lines):
      IO.print(join_lines(text_lines))

def main() -> IO(Unit):
  opened_store = MyLsmStore.open("certificate-check")
  print_scenario_result(MyLsmStore.run_sess(&2, List<&2, String>, opened_store, scenario_outcome()))
