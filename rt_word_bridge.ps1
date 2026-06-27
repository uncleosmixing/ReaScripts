param(
  [Parameter(Mandatory=$true)][ValidateSet("export","import")][string]$Mode,
  [Parameter(Mandatory=$true)][string]$DataPath,
  [Parameter(Mandatory=$true)][string]$DocxPath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Decode-Text([string]$value) {
  [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($value))
}
function Encode-Text([string]$value) {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))
}
function Xml-Escape([string]$value) {
  [Security.SecurityElement]::Escape($value)
}
function Highlight-Rgb([string]$name) {
  $colors = @{
    black="0,0,0"; blue="0,0,255"; cyan="0,255,255"; green="0,255,0"
    magenta="255,0,255"; red="255,0,0"; yellow="255,255,0"; white="255,255,255"
    darkBlue="0,0,128"; darkCyan="0,128,128"; darkGreen="0,128,0"
    darkMagenta="128,0,128"; darkRed="128,0,0"; darkYellow="128,128,0"
    darkGray="128,128,128"; lightGray="192,192,192"
  }
  $colors[$name]
}

if ($Mode -eq "export") {
  $body = New-Object Text.StringBuilder
  foreach ($line in [IO.File]::ReadAllLines($DataPath, [Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line.Split("`t")
    if ($parts.Count -lt 4) { continue }
    $id = Xml-Escape $parts[0]
    $visible = Xml-Escape ("$($parts[1])`t$(Decode-Text $parts[2])")
    $color = ""
    if ($parts[3] -match '^(\d+),(\d+),(\d+)$') {
      $hex = "{0:X2}{1:X2}{2:X2}" -f [int]$Matches[1],[int]$Matches[2],[int]$Matches[3]
      $color = "<w:color w:val=`"$hex`"/>"
    }
    [void]$body.Append(
      "<w:p><w:pPr><w:spacing w:after=`"100`"/></w:pPr>" +
      "<w:r><w:rPr><w:vanish/></w:rPr><w:t>[RTID:$id]</w:t></w:r>" +
      "<w:r><w:rPr>$color</w:rPr><w:t xml:space=`"preserve`">$visible</w:t></w:r></w:p>")
  }

  $temp = Join-Path ([IO.Path]::GetTempPath()) ("reatitles_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path (Join-Path $temp "_rels"),(Join-Path $temp "word") | Out-Null
  $utf8 = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $temp "[Content_Types].xml"),
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
    '</Types>', $utf8)
  [IO.File]::WriteAllText((Join-Path $temp "_rels\.rels"),
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
    '</Relationships>', $utf8)
  $document = '<?xml version="1.0" encoding="UTF-8"?>' +
    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
    '<w:body>' + $body.ToString() + '<w:sectPr/></w:body></w:document>'
  [IO.File]::WriteAllText((Join-Path $temp "word\document.xml"), $document, $utf8)

  if (Test-Path -LiteralPath $DocxPath) { Remove-Item -LiteralPath $DocxPath -Force }
  $zip = [IO.Compression.ZipFile]::Open($DocxPath, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($file in Get-ChildItem -LiteralPath $temp -Recurse -File) {
      $relative = $file.FullName.Substring($temp.Length).TrimStart("\","/").Replace("\","/")
      [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $file.FullName, $relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
  } finally {
    $zip.Dispose()
  }
  Remove-Item -LiteralPath $temp -Recurse -Force
  exit 0
}

$archive = [IO.Compression.ZipFile]::OpenRead($DocxPath)
try {
  $entry = $archive.GetEntry("word/document.xml")
  if (-not $entry) { throw "word/document.xml not found" }
  $reader = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
  try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
  $archive.Dispose()
}

$ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
$ns.AddNamespace("w", "http://schemas.openxmlformats.org/wordprocessingml/2006/main")
$rows = New-Object Collections.Generic.List[string]
foreach ($paragraph in $xml.SelectNodes("//w:body/w:p", $ns)) {
  $all = ($paragraph.SelectNodes(".//w:t", $ns) | ForEach-Object { $_.InnerText }) -join ""
  if ($all -notmatch '^\[RTID:([^\]]+)\]') { continue }
  $id = $Matches[1]
  $visibleParts = New-Object Collections.Generic.List[string]
  $rgb = ""
  foreach ($run in $paragraph.SelectNodes("./w:r", $ns)) {
    if ($run.SelectSingleNode("./w:rPr/w:vanish", $ns)) { continue }
    $runText = ($run.SelectNodes(".//w:t", $ns) | ForEach-Object { $_.InnerText }) -join ""
    $visibleParts.Add($runText)
    if (-not $rgb -and $runText.Length -gt 0) {
      $highlight = $run.SelectSingleNode("./w:rPr/w:highlight", $ns)
      $fontColor = $run.SelectSingleNode("./w:rPr/w:color", $ns)
      if ($highlight) {
        $rgb = Highlight-Rgb $highlight.GetAttribute("val", $ns.LookupNamespace("w"))
      } elseif ($fontColor) {
        $hex = $fontColor.GetAttribute("val", $ns.LookupNamespace("w"))
        if ($hex -match '^[0-9A-Fa-f]{6}$') {
          $rgb = "$([Convert]::ToInt32($hex.Substring(0,2),16)),$([Convert]::ToInt32($hex.Substring(2,2),16)),$([Convert]::ToInt32($hex.Substring(4,2),16))"
        }
      }
    }
  }
  $visible = $visibleParts -join ""
  $tab = $visible.IndexOf("`t")
  $text = if ($tab -ge 0) { $visible.Substring($tab + 1) } else { $visible }
  $rows.Add("$id`t$(Encode-Text $text)`t$rgb")
}
[IO.File]::WriteAllLines($DataPath, $rows, (New-Object Text.UTF8Encoding($false)))
