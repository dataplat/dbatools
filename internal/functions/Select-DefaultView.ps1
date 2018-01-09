function Select-DefaultView {
    <#

    This command enables us to send full on objects to the pipeline without the user seeing it

    See it in action in Get-DbaSnapshot and Remove-DbaDatabaseSnapshot

    a lot of this is from boe, thanks boe!
    https://learn-powershell.net/2013/08/03/quick-hits-set-the-default-property-display-in-powershell-on-custom-objects/

    TypeName creates a new type so that we can use ps1xml to modify the output
    #>

    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline = $true)]
        [object]$InputObject,
        [string[]]$Property,
        [string[]]$ExcludeProperty,
        [string]$TypeName
    )
    process {

        if ($null -eq $InputObject) { return }

        if ($TypeName) {
            $InputObject.PSObject.TypeNames.Insert(0, "dbatools.$TypeName")
        }

        if ($ExcludeProperty) {
            if ($InputObject.GetType().Name.ToString() -eq 'DataRow') {
                $ExcludeProperty += 'Item', 'RowError', 'RowState', 'Table', 'ItemArray', 'HasErrors'
            }

            $properties = ($InputObject.PsObject.Members | Where-Object MemberType -ne 'Method' | Where-Object { $_.Name -notin $ExcludeProperty }).Name
            $defaultset = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$properties)
        }
        else {
            # property needs to be string
            if ("$property" -like "* as *") {
                $newproperty = @()
                foreach ($p in $property) {
                    if ($p -like "* as *") {
                        $old, $new = $p -isplit " as "
                        # Do not be tempted to not pipe here
                        $inputobject | Add-Member -Force -MemberType AliasProperty -Name $new -Value $old -ErrorAction SilentlyContinue
                        $newproperty += $new
                    }
                    else {
                        $newproperty += $p
                    }
                }
                $property = $newproperty
            }
            $defaultset = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$Property)
        }

        $standardmembers = [System.Management.Automation.PSMemberInfo[]]@($defaultset)

        # Do not be tempted to not pipe here
        $inputobject | Add-Member -Force -MemberType MemberSet -Name PSStandardMembers -Value $standardmembers -ErrorAction SilentlyContinue

        $inputobject
    }
}
