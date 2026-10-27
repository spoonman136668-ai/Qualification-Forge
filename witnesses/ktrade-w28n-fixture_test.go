package papercustody
import ("encoding/json";"io/fs";"os";"path/filepath";"testing")
func TestW28NExportOriginalStoppedFixture(t *testing.T) {
 target,receipt:=os.Getenv("W28N_DATA_ROOT"),os.Getenv("W28N_FIXTURE_RECEIPT")
 if !filepath.IsAbs(target)||filepath.Base(target)!="data"||!filepath.IsAbs(receipt){t.Fatal("explicit absolute disposable fixture outputs required")}
 if _,e:=os.Stat(filepath.Join(filepath.Dir(target),"release-candidate-proof.json"));e!=nil{t.Fatal(e)}
 app,id,_:=w28hCompleteFixture(t)
 from,to:=filepath.Join(app,"paper-history"),filepath.Join(target,"paper-history")
 if _,e:=os.Lstat(to);!os.IsNotExist(e){t.Fatal("existing target refused")}
 e:=filepath.WalkDir(from,func(p string,d fs.DirEntry,err error)error{
  if err!=nil{return err};rel,err:=filepath.Rel(from,p);if err!=nil{return err};dst:=filepath.Join(to,rel)
  if d.Type()&os.ModeSymlink!=0{t.Fatal("fixture symlink refused")}
  if d.IsDir(){return os.Mkdir(dst,0700)}
  raw,err:=os.ReadFile(p);if err!=nil{return err};return os.WriteFile(dst,raw,0600)
 })
 if e!=nil{t.Fatal(e)}
 r,e:=ReviewExplicitW28HStoppedHistory(target,id);if e!=nil{t.Fatal(e)}
 if r.Account.Products[0].Cash!="559.7"||r.Account.Products[0].PositionQty!="1"||r.Account.Products[0].FeesPaid!="0.3"||r.Account.Products[0].FillCount!=1{t.Fatal("original financial fixture drift")}
 raw,e:=json.Marshal(map[string]string{"source_id":id,"snapshot_seal":r.SnapshotSeal,"archive_sha256":r.ArchiveSHA256,"ledger_hash":r.Account.Products[0].LedgerHash});if e!=nil{t.Fatal(e)}
 if _,e:=os.Lstat(receipt);!os.IsNotExist(e){t.Fatal("existing receipt refused")}
 if e=os.WriteFile(receipt,raw,0600);e!=nil{t.Fatal(e)}
}
