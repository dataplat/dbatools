# Write-DbaDbTableData: Settings for ConvertTo-DbaDataTable
Set-DbatoolsConfig -FullName 'commands.Write-DbaDbTableData.timespantype' -Value 'TotalMilliseconds' -Initialize -Validation string -Description "When passing random objects at Write-DbaDbTableData, it will convert them to a DataTable before writing it, using ConvertTo-DbaDataTable. This setting controls how Timespan objects are converted"
Set-DbatoolsConfig -FullName 'commands.Write-DbaDbTableData.sizetype' -Value 'Int64' -Initialize -Validation string -Description "When passing random objects at Write-DbaDbTableData, it will convert them to a DataTable before writing it, using ConvertTo-DbaDataTable. This setting controls how Size objects are converted"
Set-DbatoolsConfig -FullName 'commands.Write-DbaDbTableData.ignorenull' -Value $false -Initialize -Validation bool -Description "When passing random objects at Write-DbaDbTableData, it will convert them to a DataTable before writing it, using ConvertTo-DbaDataTable. This setting controls whether null objects will be ignored, rather than generating an empty row"
Set-DbatoolsConfig -FullName 'commands.Write-DbaDbTableData.raw' -Value $false -Initialize -Validation bool -Description "When passing random objects at Write-DbaDbTableData, it will convert them to a DataTable before writing it, using ConvertTo-DbaDataTable. This setting controls whether all properties will be stored as string (`$true) or as much as possible in their native type (`$false)"

# Resolve-DbaNetworkName
Set-DbatoolsConfig -FullName 'commands.resolve-dbanetworkname.bypass' -Value $false -Initialize -Validation bool -Description "Use input exactly as stated instead of attempting to resolve"

# Get-DbaRegServer
Set-DbatoolsConfig -FullName 'commands.get-dbaregserver.defaultcms' -Value $null -Initialize -Validation string -Description "Use a default Central Management Server"
Set-DbatoolsConfig -FullName 'commands.get-dbaregserver.includelocal' -Value $false -Initialize -Validation bool -Description "Include local servers by default"