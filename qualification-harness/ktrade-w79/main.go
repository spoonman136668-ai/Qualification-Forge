package main

import (
 "encoding/json"
 "fmt"
 "io"
 "os"
 "sort"
)
type Frame struct { Module string `json:"module"`; Version string `json:"version"`; Package string `json:"package"`; Function string `json:"function"` }
type Finding struct { OSV string `json:"osv"`; FixedVersion string `json:"fixed_version"`; Trace []Frame `json:"trace"` }
type Message struct { Config *struct{ ScannerVersion string `json:"scanner_version"`; GoVersion string `json:"go_version"`; DB string `json:"db"`; DBLastModified string `json:"db_last_modified"` } `json:"config"`; Finding *Finding `json:"finding"` }
func main(){
 if len(os.Args)!=4 { panic("W79_ARGUMENTS") }
 f,e:=os.Open(os.Args[1]);if e!=nil{panic("W79_SCAN_FILE")};defer f.Close()
 d:=json.NewDecoder(f);configs:=0;reachable:=map[string]Finding{};imported:=map[string]bool{}
 goVersion:="";scannerVersion:="";database:="";modified:=""
 for{var m Message;e=d.Decode(&m);if e==io.EOF{break};if e!=nil{panic("W79_MALFORMED_SCAN_JSON")}
 if m.Config!=nil{configs++;goVersion=m.Config.GoVersion;scannerVersion=m.Config.ScannerVersion;database=m.Config.DB;modified=m.Config.DBLastModified}
 if m.Finding!=nil{v:=*m.Finding;if len(v.Trace)==0{panic("W79_MISSING_TRACE")};imported[v.OSV]=true;if v.Trace[0].Function!=""{reachable[v.OSV+"|"+v.Trace[0].Module+"|"+v.Trace[0].Package+"|"+v.Trace[0].Function]=v}}
 }
 if configs!=1||goVersion==""||scannerVersion==""{panic("W79_SCAN_CONFIG_MISSING")}
 keys:=[]string{};for k:=range reachable{keys=append(keys,k)};sort.Strings(keys)
 rows:=[]map[string]string{};for _,k:=range keys{v:=reachable[k];s:=v.Trace[0];rows=append(rows,map[string]string{"id":v.OSV,"module":s.Module,"version":s.Version,"package":s.Package,"function":s.Function,"fixed_version":v.FixedVersion})}
 out:=map[string]any{"schema":"ktrade.security.govulncheck.scope.v1","scope":os.Args[2],"go_version":goVersion,"scanner_version":scannerVersion,"database":database,"database_modified":modified,"affected_vulnerability_ids":len(imported),"reachable_symbol_findings":len(rows),"findings":rows,"zero_reachable_known_vulnerabilities":len(rows)==0}
 b,e:=json.Marshal(out);if e!=nil{panic("W79_SUMMARY")};if os.WriteFile(os.Args[3],b,0600)!=nil{panic("W79_SUMMARY_WRITE")};fmt.Println("W79_SECURITY_SUMMARY="+string(b))
}
