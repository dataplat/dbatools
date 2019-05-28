function Get-ExportFilePath ($Path, $FilePath, $Type, $ServerName) {
    return "C:\temp\test.txt"
    #$FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type dacpac -ServerName $instance

    $cleaninstance = $instance.ToString().Replace('\', '-')

    if ($fileName) {
        $currentFileName = $fileName
    } else {
        if ($Type -eq 'Dacpac') { $ext = 'dacpac' }
        elseif ($Type -eq 'Bacpac') { $ext = 'bacpac' }
        $currentFileName = Join-Path $parentFolder "$cleaninstance-$dbname.$ext"
    }

    if ($FilePath) { return $FilePath }
    $type = (Get-PSCallStack)[1].Command.ToString().Replace("Export-Dba", "").ToLower()

    $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
    if (-not $FilePath -and (Test-Bound -Parameter Path)) {
        $FilePath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timenow-credentials.sql"
    } elseif (-not $FilePath) {
        if (Test-Path $Path -PathType Container) {
            $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
            $FilePath = Join-Path -Path $Path -ChildPath "$($server.name.replace('\', '$'))-$timenow-credentials.sql"
        } elseif (Test-Path $Path -PathType Leaf) {
            if ($SqlInstance.Count -gt 1) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $PathData = Get-ChildItem $Path
                $FilePath = "$($PathData.DirectoryName)\$($server.name.replace('\', '$'))-$timenow-$($PathData.Name)"
            } else {
                $FilePath = $Path
            }
        }
    }
    Remove-InvalidFileNameChars -Name $xes.Name

    #Resolve-Path too
}