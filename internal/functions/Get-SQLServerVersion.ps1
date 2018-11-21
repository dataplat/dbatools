function Get-SQLServerVersion {
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )
    begin {
    }
    process {
        $versions = @()
        try {
            $sqlComponents = Get-SQLInstanceComponent -ComputerName $ComputerName
            foreach ($component in $sqlComponents) {
                $currentVersion = Get-DbaBuildReference -Build $component.Version
                $versions += $currentVersion | Add-Member -Name 'Edition' -MemberType NoteProperty -Value $component.Edition -PassThru
            }
        } catch {
            Stop-Function -Message "Failed to process SQL versions" -ErrorRecord $_
            return
        }
    }
    end {
        $versions
    }
}