Write-Host -ForeGroundColor cyan "Fixing Opencover"
[System.Xml.XmlDocument]$file = New-Object System.Xml.XmlDocument
$file.load("$($env:APPVEYOR_BUILD_FOLDER)\coverage_orig.xml")
$xml_modules = $file.SelectNodes("/CoverageSession/Modules/Module/ModuleName[text() = 'dbatools'][1]")
foreach($fpath in $xml_modules.ParentNode.Files.File) {
    $fpath.fullPath = $fpath.fullPath.Replace("$($env:APPVEYOR_BUILD_FOLDER)\", '').Replace('\', '/')
}
$file.save("$($env:APPVEYOR_BUILD_FOLDER)\coverage.xml")

