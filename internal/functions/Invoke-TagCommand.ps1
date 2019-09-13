function Invoke-TagCommand ([string]$Tag, [string]$Keyword) {
    <#
.SYNOPSIS
    An internal command, feel free to ignore.

.EXAMPLE
    Tag-Command -Tag Restore -Keyword Restore
    Tag-Command -Tag Backup -Keyword Backup
    Tag-Command -Tag Orphan -Keyword Orphan
    Tag-Command -Tag DisasterRecovery -Keyword Attach
    Tag-Command -Tag DisasterRecovery -Keyword Detach
    Tag-Command -Tag Snapshot -Keyword Snapshot
    Tag-Command -Tag Memory -Keyword Memory
    Tag-Command -Tag DisasterRecovery -Keyword Restore
    Tag-Command -Tag DisasterRecovery -Keyword Backup
    Tag-Command -Tag Storage -Keyword disk
    Tag-Command -Tag Storage -Keyword storage
    Tag-Command -Tag Migration -Keyword "Copy-"
    Tag-Command -Tag SPN -Keyword Kerberos
    Tag-Command -Tag SPN -Keyword SPN
    Tag-Command -Tag CIM -Keyword CimSession
    Tag-Command -Tag SQLWMI -Keyword Invoke-ManagedComputerCommand
    Tag-Command -Tag WSMan -Keyword Invoke-Command

    #>

    $tagsRex = ([regex]'(?m)^[\s]{0,15}Tags:(.*)$')
    $modulepath = (Get-Module -Name dbatools).Path
    $directory = Split-Path $modulepath
    $basedir = "$directory\functions\"
    Import-Module $modulepath -force
    $allfiles = Get-ChildItem $basedir
    foreach ($f in $allfiles) {
        if ($f -eq "Find-DbaCommand.ps1") { continue }

        $content = Get-Content $f.fullname
        if ($content -like "*$keyword*") {
            Write-Message -Level Warning -Message "$f needs a tag tag"
            $cmdname = $f.name.replace('.ps1', '')

            $fullhelp = Get-Help $cmdname -full

            $as = $fullhelp.alertset | Out-String

            $tags = $tagsrex.Match($as).Groups[1].Value

            if ($tags) {
                $tags = $tags.ToString().split(',').Trim()
                Write-Message -Level Warning -Message "adding tags to existing ones"
                if ($tag -in $tags) {
                    Write-Message -Level Warning -Message "tag $tag is already present"
                    continue
                }
                $out = @()
                foreach ($line in $content) {
                    if ($line.trim().startsWith('Tags:')) {
                        $out += "$line, $tag"
                    } else {
                        $out += $line
                    }
                }
                Write-Message -Level Warning -Message "replacing content into $($f.fullname)"
                $out -join "`r`n" | Set-Content $f.fullname -Encoding UTF8

            } else {
                Write-Message -Level Warning -Message "need to add tags"
                $out = @()
                foreach ($line in $content) {
                    if ($line.startsWith('.NOTES')) {
                        $out += '.NOTES'
                        $out += "Tags: $tag"
                    } else {
                        $out += $line
                    }
                }
                Write-Message -Level Warning -Message "replacing content into $($f.fullname)"
                $out -join "`r`n" | Set-Content $f.fullname -Encoding UTF8
            }
        }
    }
}