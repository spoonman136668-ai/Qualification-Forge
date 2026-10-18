package main
import (
 "crypto/sha256"
 "encoding/hex"
 "flag"
 "fmt"
 "go/ast"
 "go/parser"
 "go/token"
 "os"
 "path/filepath"
 "reflect"
 "regexp"
 "sort"
 "strconv"
 "strings"
)
type field struct{ name, typ string }
type family struct{ tag string; members []field }
type group struct{ key,sample string; members,warnings,families int; files []string }
var diagnostic=regexp.MustCompile("([^\\s:]+\\.go):([0-9]+):([0-9]+):\\s*(.+)$")
func parseStructs(file string)([]family,int,error){
 fs:=token.NewFileSet()
 parsed,err:=parser.ParseFile(fs,file,nil,parser.AllErrors|parser.SkipObjectResolution)
 if err!=nil{return nil,0,err}
 all:=[]family{};total:=0
 ast.Inspect(parsed,func(n ast.Node)bool{
  st,ok:=n.(*ast.StructType);if !ok{return true}
  grouped:=map[string][]field{}
  for _,f:=range st.Fields.List {
   if f.Tag==nil{continue}
   literal,err:=strconv.Unquote(f.Tag.Value);if err!=nil{continue}
   key:=strings.Split(reflect.StructTag(literal).Get("json"),",")[0]
   if key==""||key=="-"{continue}
   for _,name:=range f.Names{
    typ:="other";if ident,ok:=f.Type.(*ast.Ident);ok{typ=ident.Name}
    grouped[key]=append(grouped[key],field{name.Name,typ})
   }
  }
  keys:=[]string{};for key,members:=range grouped{if len(members)>1{keys=append(keys,key)}};sort.Strings(keys)
  for _,key:=range keys{members:=grouped[key];all=append(all,family{key,members});total+=len(members)-1}
  return true
 })
 return all,total,nil
}
func signature(families []family)string{
 parts:=[]string{}
 for _,f:=range families{
  names:=[]string{};for _,m:=range f.members{names=append(names,m.name+":"+m.typ)}
  sort.Strings(names);parts=append(parts,f.tag+"{"+strings.Join(names,",")+"}")
 }
 sort.Strings(parts);return strings.Join(parts,"|")
}
func classify(msg string)string{
 l:=strings.ToLower(msg)
 switch{
 case strings.Contains(l,"repeats json tag"):return "duplicate_json_tag"
 case strings.Contains(l,"bad syntax for struct tag"):return "invalid_tag_syntax"
 case strings.Contains(l,"not compatible with reflect.structtag.get"):return "incompatible_tag"
 case strings.Contains(l,"unexported field"):return "unexported_tag"
 default:return "other"
 }
}
func main(){
 root:=flag.String("source","","exact source root")
 log:=flag.String("log","","go vet output path")
 expected:=flag.Int("expected",0,"expected count")
 flag.Parse()
 if *root==""||*log==""||*expected<=0{panic("missing args")}
 data,err:=os.ReadFile(*log);if err!=nil{panic(err)}
 count:=0;byFile:=map[string][]string{};byKind:=map[string]int{};examples:=map[string]string{}
 for _,line:=range strings.Split(string(data),"\n"){
  m:=diagnostic.FindStringSubmatch(strings.TrimSpace(line));if len(m)!=5{continue}
  msg:=m[4]; name:=filepath.Base(strings.ReplaceAll(m[1],"\\","/"));kind:=classify(msg)
  count++;byFile[name]=append(byFile[name],msg);byKind[kind]++
  if examples[kind]==""{examples[kind]=msg}
 }
 fmt.Printf("R25C10_DIAGNOSTICS=%d\n",count)
 if count!=*expected{panic(fmt.Sprintf("diagnostics changed expected=%d actual=%d",*expected,count))}
 names:=[]string{};for name:=range byFile{names=append(names,name)};sort.Strings(names)
 groups:=map[string]*group{};unexplained:=[]string{};astTotal:=0
 for _,name:=range names{
  families,warnings,err:=parseStructs(filepath.Join(*root,"pkg",name));if err!=nil{panic("parse "+name+": "+err.Error())}
  if len(families)==0{unexplained=append(unexplained,fmt.Sprintf("%s:vet=%d no-collision",name,len(byFile[name])));continue}
  key:=signature(families);h:=sha256.Sum256([]byte(key));hash:=hex.EncodeToString(h[:])
  g:=groups[hash];if g==nil{g=&group{key:key,sample:name};groups[hash]=g}
  g.files=append(g.files,name);g.warnings+=warnings;g.families+=len(families)
  for _,f:=range families{g.members+=len(f.members)}
  astTotal+=warnings
  if warnings!=len(byFile[name]){unexplained=append(unexplained,fmt.Sprintf("%s:vet=%d ast=%d",name,len(byFile[name]),warnings))}
 }
 kinds:=[]string{};for k:=range byKind{kinds=append(kinds,k)};sort.Strings(kinds)
 for _,k:=range kinds{fmt.Printf("R25C10_WARNING_KIND=%s COUNT=%d EXAMPLE=%q\n",k,byKind[k],examples[k])}
 hashes:=[]string{};for h:=range groups{hashes=append(hashes,h)}
 sort.Slice(hashes,func(i,j int)bool{return groups[hashes[i]].warnings>groups[hashes[j]].warnings})
 for _,h:=range hashes{
  g:=groups[h]
  fmt.Printf("R25C10_EQUIV_GROUP=%s FILES=%d AST_WARNINGS=%d COLLISION_FIELDS=%d FAMILIES=%d SAMPLE=%s\n",h,len(g.files),g.warnings,g.members,g.families,g.sample)
  fmt.Printf("R25C10_EQUIV_SIGNATURE=%s %s\n",h,g.key)
  fmt.Printf("R25C10_EQUIV_FILES=%s %s\n",h,strings.Join(g.files,","))
 }
 sort.Strings(unexplained)
 fmt.Printf("R25C10_VET_FILES=%d\n",len(names))
 fmt.Printf("R25C10_AST_DUPLICATE_WARNINGS=%d\n",astTotal)
 fmt.Printf("R25C10_UNEXPLAINED_FILES=%d\n",len(unexplained))
 for _,u:=range unexplained{fmt.Println("R25C10_UNEXPLAINED="+u)}
 f444,w444,err:=parseStructs(filepath.Join(*root,"pkg","p11b_t444_explicit_new_repro_only_release_readiness_governance_closeout_belonging_pin.go"))
 if err!=nil{panic(err)}
 fmt.Printf("R25C10_T444_DUPLICATE_FAMILIES=%d AST_WARNINGS=%d\n",len(f444),w444)
 if len(unexplained)==0{fmt.Println("R25C10_CLASSIFICATION=AST_GROUPING_COMPLETE")}else{fmt.Println("R25C10_CLASSIFICATION=REQUIRES_NONCOLLISION_REVIEW")}
}
