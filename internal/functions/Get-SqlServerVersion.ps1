function Get-SqlServerVersion {
    <#
    .SYNOPSIS
        Returns a build reference for each SQL Server installation found on a computer.
    .DESCRIPTION
        Gets information from internal Get-SqlInstanceComponent and adjusts output to leverage
        Get-DbaBuildReference to get an appropriate information about the current build.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )
    begin {
        $versions = @()
    }
    process {
        try {
            $sqlComponents = Get-SqlInstanceComponent -ComputerName $ComputerName -Credential $Credential
            foreach ($component in $sqlComponents) {
                #Replace first decimal of the minor build with a 0, since we're using build numbers here
                #Refer to https://sqlserverbuilds.blogspot.com/
                Write-Message -Level Debug -Message "Converting version $($component.Version) to [version]"
                $newVersion = New-Object -TypeName System.Version -ArgumentList ([string]$component.Version)
                $newVersion = New-Object -TypeName System.Version -ArgumentList ($newVersion.Major , ($newVersion.Minor - $newVersion.Minor % 10), $newVersion.Build)
                Write-Message -Level Debug -Message "Converted version $($component.Version) to $newVersion"
                $currentVersion = Get-DbaBuildReference -Build $newVersion
                $versions += $currentVersion | Add-Member -Name 'Edition' -MemberType NoteProperty -Value $component.Edition -PassThru
            }
        } catch {
            Stop-Function -Message "Failed to process SQL versions" -ErrorRecord $_ -EnableException $false
        }
    }
    end {
        $versions
    }
}