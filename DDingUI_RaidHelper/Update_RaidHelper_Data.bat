@echo off
setlocal
chcp 65001 >nul
title DDingUI RaidHelper - Warcraft Logs Data Update

pushd "%~dp0"

where py >nul 2>nul
if not errorlevel 1 (
    set "RAIDHELPER_PYTHON=py -3 -u"
) else (
    where python >nul 2>nul
    if errorlevel 1 (
        echo [ERROR] Python 3 was not found.
        echo Install Python 3, then run this file again.
        echo.
        pause
        popd
        exit /b 1
    )
    set "RAIDHELPER_PYTHON=python -u"
)

echo Updating Mythic and Heroic data for every boss...
echo Collecting top 10 HPS characters for each healer specialization,
echo including cooldowns, talents, and secondary-stat averages.
echo Reserving the next 2 ranked kills as independent timing validation logs.
echo Incomplete phase metadata is skipped and backfilled from the next ranks.
echo This can take a while. Cached reports make later updates faster.
echo.

%RAIDHELPER_PYTHON% tools\update_wcl.py update --difficulty 5 4 --limit 10 --validation-limit 2 --healer-limit 10 --workers 8
set "RAIDHELPER_EXIT=%ERRORLEVEL%"

echo.
if "%RAIDHELPER_EXIT%"=="0" (
    echo [OK] Data\Generated.lua was updated successfully.
    echo Reload World of Warcraft to use the new data.
) else (
    echo [ERROR] Update failed. Review the message above.
)

echo.
pause
popd
exit /b %RAIDHELPER_EXIT%
