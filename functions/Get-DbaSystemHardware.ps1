function Get-DbaSystemHardware {
    <#
	.SYNOPSIS
	Gets general hardware information for a server.

	.DESCRIPTION
	 Returns a custom object of the hardware information for a server, includes most common information used for inventory.

	.PARAMETER ComputerName
	The server that you are connecting to.

	.PARAMETER Credential
	Alternative credential to utilize for connecting to the server, where supported.

	.PARAMETER Silent
	Use this switch to disable any kind of verbose messages

	.NOTES
	Original Author: Shawn Melton (@wsmelton)
	Tags: SystemInfo

	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaSystemHardware

	.EXAMPLE
	Get-DbaSystemHardware -ComputerName localhost
	Returns hardware information of the local server

	.EXAMPLE
	Get-DbaSystemHardware -ComputerName localhost, sql2016
	Returns hardware information for the local and sql2016 servers
	#>

    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$ComputerName,
        [System.Management.Automation.PSCredential]$Credential,
        [switch]$Silent
    )

    BEGIN {
        <# initial notes #>
		## Main work on this will not begin until the new remote management functions are merged to development (https://github.com/sqlcollaborative/dbatools/pull/916)
        <#
1) win32 Clases to hit:
	- Processor
		Name
		Description
		Manufacturer
		DeviceID
		Status
		ThreadCount
		NumberOfCores
		NumberOfLogicalProcessors
		AddressWidth
		CurrentClockSpeed
		MaxClockSpeed
	- SystemEnclosure
		Manufacture
		Model
		SerialNumber
		SKU
		Version
	- NetworkAdapter (where MACAddress - to filter out non-essential devices)
		DeviceID
		Name
		AdapterType
		InterfaceIndex
		MACAddress
		Manufacturer
		PhysicalAdapter
		ProductName
		#>
    }

    PROCESS {
        foreach ($server in $ComputerName) {
            Write-Message -Level Verbose -Message "Attempting to connect to $server"

            try {

            }
            catch {
                Stop-Function -Message "Can't connect to $server or access denied. Skipping." -Continue
            }

            foreach ($object in $categories) {
                Write-Message -Level Verbose -Message "Processing $object"
                Add-Member -InputObject $object -MemberType NoteProperty ComputerName -value $server.NetName
                Add-Member -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                Add-Member -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                # Select all of the columns you'd like to show
                Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, ID, Name, Whatever, Whatever2
            } #foreach object
        } #foreach server
    } # process
} #function
