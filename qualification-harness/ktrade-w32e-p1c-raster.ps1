function Read-W32ECoordinates([string]$phase){
  $out=Join-Path $env:RUNNER_TEMP ('w32e-p1c-'+$phase+'.json')
  $observationLog=& node (Join-Path $env:GITHUB_WORKSPACE 'witness/qualification-harness/ktrade-w32e-p1c-observe.cjs') $debugPort $phase $out
  if($LASTEXITCODE -ne 0){throw ('W32E_P1C_READ_ONLY_COORDINATES_FAILED_'+$phase)}
  Write-Host ($observationLog -join "`n")
  return Get-Content -LiteralPath $out -Raw|ConvertFrom-Json
}
function Capture-W32EMapped([object]$proc,[object]$d){
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $bounds=$null
  foreach($el in $all){try{if($el.Current.Name -ceq 'Pine indicator pane' -and !$el.Current.IsOffscreen){$bounds=$el.Current.BoundingRectangle;break}}catch{}}
  if($null -eq $bounds -or $bounds.IsEmpty){throw 'W32E_P1C_OWNED_PANE_ANCHOR_ABSENT'}
  $scale=$bounds.Width/[double]$d.pane.width
  if($scale -lt .75 -or $scale -gt 2.5 -or [Math]::Abs($bounds.Height-$d.pane.height*$scale) -gt 2){throw 'W32E_P1C_OS_CSS_GEOMETRY_MISMATCH'}
  [void][W32ENativeInput]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 300
  if([W32ENativeInput]::GetForegroundWindow() -ne $proc.MainWindowHandle){throw 'W32E_P1C_CAPTURE_FOREIGN_FOCUS'}
  $result=@{scale=$scale}
  foreach($kind in @('pine','volume')){
    $r=$d.$kind
    $left=[int][Math]::Round($bounds.Left+($r.x-$d.pane.x)*$scale)
    $top=[int][Math]::Round($bounds.Top+($r.y-$d.pane.y)*$scale)
    $w=[int][Math]::Round($r.width*$scale);$h=[int][Math]::Round($r.height*$scale)
    if($w -lt 100 -or $h -lt 20){throw 'W32E_P1C_NATIVE_CHART_EMPTY'}
    $outer=$root.Current.BoundingRectangle
    if($left -lt $outer.Left -or $top -lt $outer.Top -or $left+$w -gt $outer.Right+1 -or $top+$h -gt $outer.Bottom+1){throw 'W32E_P1C_NATIVE_RECT_NOT_OWNED'}
    $bmp=[Drawing.Bitmap]::new($w,$h);$gfx=[Drawing.Graphics]::FromImage($bmp)
    try{
      $gfx.CopyFromScreen($left,$top,0,0,$bmp.Size,[Drawing.CopyPixelOperation]::SourceCopy)
      $mem=[IO.MemoryStream]::new();$sha=[Security.Cryptography.SHA256]::Create()
      try{$bmp.Save($mem,[Drawing.Imaging.ImageFormat]::Png);$hash=[Convert]::ToHexString($sha.ComputeHash($mem.ToArray())).ToLowerInvariant()}finally{$mem.Dispose();$sha.Dispose()}
      $pixels=[Collections.Generic.List[object]]::new()
      for($y=0;$y -lt $h;$y++){for($x=0;$x -lt $w;$x++){
        $px=$bmp.GetPixel($x,$y)
        if($px.R -ge 170 -and $px.B -ge 140 -and $px.G -lt 130 -and ($px.R+$px.B-2*$px.G) -ge 200){$pixels.Add([pscustomobject]@{x=$x;y=$y})}
      }}
      $result[$kind]=[pscustomobject]@{width=$w;height=$h;hash=$hash;pixels=$pixels;left=$left;top=$top}
    }finally{$gfx.Dispose();$bmp.Dispose()}
  }
  return [pscustomobject]$result
}
function Check-W32EExactRaster([object]$before,[object]$after,[object]$d0,[object]$d1){
  if($before.scale -ne $after.scale){throw 'W32E_P1C_SCALE_CHANGED'}
  foreach($key in @('volume_rows','candle_rows','volume_range','volume')){
    if(($d0.$key|ConvertTo-Json -Compress -Depth 6) -cne ($d1.$key|ConvertTo-Json -Compress -Depth 6)){throw ('W32E_P1C_ORIGINAL_VOLUME_OR_CANDLE_CHANGED_'+$key)}
  }
  if($before.volume.hash -cne $after.volume.hash){
    Write-Output ('W32E_P1C_VOLUME_HASH_DIFFER='+(@{before=$before.volume.hash;after=$after.volume.hash;range_before=$d0.volume_range;range_after=$d1.volume_range;rect_before=$d0.volume;rect_after=$d1.volume}|ConvertTo-Json -Compress))
    throw 'W32E_P1C_VOLUME_RASTER_CHANGED'
  }
  if($before.pine.pixels.Count -ne 0 -or $after.pine.pixels.Count -lt 80 -or $after.volume.pixels.Count -ne 0){throw 'W32E_P1C_PLOT_NOT_ISOLATED_TO_PINE'}
  $radius=[int][Math]::Ceiling(3*$after.scale)
  $hits=0;$negative=0;$points=@();$errors=@()
  for($i=2;$i -lt 30;$i++){
    $c=$d1.rows[$i];$x=[double]$c.pine_x*$after.scale;$y=[double]$c.pine_y*$after.scale
    if($x -lt 0 -or $x -ge $after.pine.width -or $y -lt 0 -or $y -ge $after.pine.height){throw ('W32E_P1C_POINT_OUTSIDE_VIEW_'+$i)}
    $local=@($after.pine.pixels|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and [Math]::Abs($_.y-$y) -le $radius})
    if($local.Count -gt 0){$hits++;$dist=($local|ForEach-Object {[Math]::Sqrt([Math]::Pow($_.x-$x,2)+[Math]::Pow($_.y-$y,2))}|Measure-Object -Minimum).Minimum;$errors+=$dist}
    # A 20 CSS-pixel vertical displacement must not match the measured line.
    $wrongY=if($y+20*$after.scale -lt $after.pine.height){$y+20*$after.scale}else{$y-20*$after.scale}
    $wrong=@($after.pine.pixels|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and [Math]::Abs($_.y-$wrongY) -le $radius})
    if($wrong.Count -gt 0){$negative++}
    $points+=@{bar=$i;time=$c.time;expected_sma=99+$i;x=$x;y=$y;matched=$local.Count -gt 0;wrong_y_matched=$wrong.Count -gt 0}
  }
  Write-Output ('W32E_P1C_NATIVE_POINTS='+($points|ConvertTo-Json -Compress))
  if($hits -ne 28 -or $negative -ne 0){throw ('W32E_P1C_POINT_RASTER_FAILED_hits_'+$hits+'_negative_'+$negative)}
  Write-Output ('W32E_P1C_EXACT_RASTER_PROOF='+(@{source='1c399965d8ab88a42e25f9997e0db15dec15e6b0';mapped_points=$hits;displaced_negative_hits=$negative;max_nearest_pixel_distance=($errors|Measure-Object -Maximum).Maximum;physical_tolerance=$radius;scale=$after.scale;baseline_pine_pixels=$before.pine.pixels.Count;applied_pine_pixels=$after.pine.pixels.Count;volume_pine_pixels=$after.volume.pixels.Count;volume_rows_unchanged=30;volume_png_before=$before.volume.hash;volume_png_after=$after.volume.hash;pine_png_sha256=$after.pine.hash;pine_width=$after.pine.width;pine_height=$after.pine.height;observer='loopback CDP fixed read-only original chart coordinate getters; no mutation';input='Win32/UIA/clipboard';capture='Windows Graphics.CopyFromScreen'}|ConvertTo-Json -Compress))
  Write-Output '::notice::W32E_P1C_NATIVE_28_POINT_COORDINATES_AND_VOLUME_RASTER_IDENTITY=PASS'
}
