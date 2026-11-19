$files = Get-ChildItem .\temp\linux | Where-Object Name -notmatch sqlpackage
foreach ($file in $files) {
    $fullname = $file.Name
    $replace = Get-ChildItem .\temp\sp\$fullname
    Get-ChildItem $replace -ErrorAction Stop
    Remove-Item $file.FullName
    $output = ./temp/linux/sqlpackage | Out-String
    if ($output -notmatch "Specifies a name value pair") {
        Copy-Item $replace -Destination ./temp/linux
    }
}