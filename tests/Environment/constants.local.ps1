# constants.local.ps1.example
# Copy this file to constants.local.ps1 and customize the values as needed.

# Modify the $config hashtable to include your custom configurations.

$config['host1'] = $(hostname)    # Replace with your primary server for most of the tests
$config['host2'] = 'SQL2022'       # Replace with your secondary server for tests that need an instance on a different host


# Define your local SQL Server instances
$config['instance1'] = "$($config['host1'])"                 # Replace with your first SQL Server instance
# Should be a default instance that listens on 1433 because of:
# Test-DbaConnection.Tests.ps1
$config['instance2'] = "$($config['host1'])\SQLInstance2"    # Replace with your second SQL Server instance
$config['instance3'] = "$($config['host1'])\SQLInstance3"    # Replace with your third SQL Server instance

# Array of SQL Server instances
$config['instances'] = @($config['instance1'], $config['instance2'])

# SQL Server credentials
# Replace 'YourPassword' with your actual password and 'sa' with your username if different
$securePassword = ConvertTo-SecureString "P#ssw0rd" -AsPlainText -Force
$config['SqlCred'] = New-Object System.Management.Automation.PSCredential ("sa", $securePassword)

# Default parameter values for the tests
# Try to use windows integrated auth if possible
#$config['PSDefaultParameterValues'] = @{
#    "*:SqlCredential" = $config['SqlCred']
#}

# Additional configurations
$config['dbatoolsci_computer'] = $config['host1']    # Replace if your CI computer is different

# If using SQL authentication for Instance2, specify the username and password
#$config['instance2SQLUserName'] = $null        # Replace with username if applicable
#$config['instance2SQLPassword'] = $null        # Replace with password if applicable

# Detailed instance name for Instance2 (if needed)
$config['instance2_detailed'] = "$($config['host1']),14333\SQLInstance2"  # Adjust port and instance name as necessary

# Path to your local AppVeyor lab repository (if applicable)
$config['appveyorlabrepo'] = "C:\GitHub\appveyor-lab"        # Replace with the correct path

# SSIS Server instance
#$config['ssisserver'] = "localhost\SQLInstance2"              # Replace if using a different SSIS server

# Azure Blob storage configurations (if applicable)
#$config['azureblob'] = "https://yourstorageaccount.blob.core.windows.net/sql"
#$config['azureblobaccount'] = "yourstorageaccount"            # Replace with your Azure Storage account name

# Azure SQL Server configurations (if applicable)
#$config['azureserver'] = "yourazureserver.database.windows.net"  # Replace with your Azure SQL Server name
#$config['azuresqldblogin'] = "yourusername@yourdomain.com"       # Replace with your Azure SQL DB login

# Path to a large database backup file (if needed for tests)
#$config['bigDatabaseBackup'] = "C:\path\to\yourdatabase.bak"     # Replace with the path to your .bak file

# URL to download the large database backup file
#$config['bigDatabaseBackupSourceUrl'] = "https://yoururl.com/yourdatabase.bak"  # Replace with the actual URL
