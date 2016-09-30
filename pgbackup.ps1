
#Set-ExecutionPolicy Unrestricted
$BackupRoot = 'G:\basesback';
$BackupLabel = (Get-Date -Format 'yyyy-MM-dd_HHmmss');
$PgBackupExe = 'C:\Program Files\PostgreSQL\9.2.4-1.1C\bin\pg_dump.exe';
$DBIP='data01';
$DBPort='5432';
$DBName='postgres';
$DBUser='postgres';
$DBPass='';
$basesmass=@();

if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe")) {throw "$env:ProgramFiles\7-Zip\7z.exe needed"} 
set-alias sz "$env:ProgramFiles\7-Zip\7z.exe" 


$ExpireDate = (Get-Date).AddDays(-17);


# log settings
$EventSource = 'pg_basebackup';

#bases list from pg server
function Getbaselist{
    $basesmass=@();
    $DBConnectionString = "Driver={PostgreSQL Unicode(x64)};Server=$DBIP;Port=$DBPort;Database=$DBName;Uid=$DBUser;Pwd=$DBPass;"
    $DBConn = New-Object System.Data.Odbc.OdbcConnection;
    $DBConn.ConnectionString = $DBConnectionString;
    $DBConn.Open();
    $DBCmd = $DBConn.CreateCommand();
    $DBCmd.CommandText = "SELECT datname FROM pg_database;";
    $result = $DBCmd.ExecuteReader();
    #$result | Get-Member;
    while($result.Read()){
                 $basesmass+=$result.GetValue(0);
            }
    $DBConn.Close();
    return $basesmass
}

# log erros to Windows Application Event Log
function Log([string] $message, [System.Diagnostics.EventLogEntryType] $type){
    # create EventLog source
    if (![System.Diagnostics.EventLog]::SourceExists($EventSource)){
        New-Eventlog -LogName 'Application' -Source $EventSource;
    }

    # write to EventLog
    Write-EventLog -LogName 'Application'`
        -Source $EventSource -EventId 1 -EntryType $type -Message $message;

}
 
# remove expired backups
function Purge([string] $backupRoot, [DateTime] $expireDate){
    # remove old files
    Get-ChildItem -Path $backupRoot -Recurse -Force -File | 
        Where-Object { $_.CreationTime -lt $expireDate } | 
        Remove-Item -Force;
 
    # remove old dirs
    Get-ChildItem -Path $backupRoot -Recurse -Force -Directory | 
        Where-Object { (Get-ChildItem -Path $_.FullName -Recurse -Force -File) -eq $null } | 
        Where-Object { $_.CreationTime -lt $expireDate } | 
        Remove-Item -Force -Recurse;
}


$basesmass=Getbaselist


$PgBackupErrorLog = Join-Path $BackupRoot ($BackupLabel + '-tmp.log');

# execution time
$StartTS = (Get-Date);
$BackupLabel = "_"+$BackupLabel+".sql";

foreach($base in $basesmass){
            $BackupDir = Join-Path $BackupRoot $base;
            $Backupbasefile= $BackupDir+"\"+$base+$BackupLabel;
            if (!(Test-Path -path $BackupDir))
                {
                    New-Item -ItemType Directory -Force -Path $BackupDir;
                }

            # start pg_basebackup
            try
                {
                    #Start-Process $PgBackupExe -ArgumentList "-U postgres", "-f $Backupbasefile", $base -Wait -NoNewWindow;
                    Start-Process $PgBackupExe -ArgumentList "-U postgres", "-f $Backupbasefile", $base -Wait -NoNewWindow -RedirectStandardError $PgBackupErrorLog;
                    sz a -mx5 $Backupbasefile+".zip" $Backupbasefile
                    remove-item -path $Backupbasefile -force
                }
            catch
                {
                    Write-Error $_.Exception.Message;
                    Log $_.Exception.Message Error;
                    Exit 1;
                }

}

# check pg_basebackup output
If (Test-Path $PgBackupErrorLog){
 
    # read errors
    $errors = Get-Content $PgBackupErrorLog;
 
    If($errors -eq $null){
        # backup successful, purge old backups
        Purge $BackupRoot $ExpireDate;
    }
    else{
        # write error to Event Log
        Log $errors Error;
    }
 
    # delete tmp error log
    Remove-Item $PgBackupErrorLog -Force;
}

# Log backup duration
$ElapsedTime = $(get-date) - $StartTS;
Log "Backup done in $($ElapsedTime.TotalMinutes) minutes" Information;