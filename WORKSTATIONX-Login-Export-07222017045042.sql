
/*			
	Created by BASE\ctrlb using dbatools Export-DbaScript for objects on WORKSTATIONX at 07/22/2017 04:50:43
	See https://dbatools.io/Export-DbaScript for more information
*/
/*    ==Scripting Parameters==

    Source Server Version : SQL Server 2008 R2 (10.50.4042)
    Source Database Engine Edition : Microsoft SQL Server Express Edition
    Source Database Engine Type : Standalone SQL Server

    Target Server Version : SQL Server 2008
    Target Database Engine Edition : Microsoft SQL Server Express Edition
    Target Database Engine Type : Standalone SQL Server
*/

/* For security reasons the login is created disabled and with a random password. */
CREATE LOGIN [tester] WITH PASSWORD=N'p8wediP5BzTygOACIY/Z0/dv5Cgfhgr4K3XJkSohEpY=', DEFAULT_DATABASE=[tempdb], DEFAULT_LANGUAGE=[Français], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
ALTER LOGIN [tester] DISABLE
EXEC sys.sp_addsrvrolemember @loginame = N'tester', @rolename = N'sysadmin'
