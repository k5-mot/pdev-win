@echo off
setlocal

set "ROOT=C:\Users\merry\Desktop\pdev-win\pdev"
set "LOCAL=%ROOT%\.local"
set "OPT=%LOCAL%\opt"
set "BIN=%LOCAL%\bin"
set "TMP=%LOCAL%\tmp"
set "CONFIG=%ROOT%\.config"
set "HOME=%LOCAL%\home"
set "USERPROFILE=%HOME%"
set "APPDATA=%CONFIG%\appdata\Roaming"
set "LOCALAPPDATA=%LOCAL%\appdata\Local"
set "XDG_CONFIG_HOME=%CONFIG%"
set "XDG_CACHE_HOME=%LOCAL%\cache"
set "TEMP=%LOCAL%\tmp"
set "TMP=%LOCAL%\tmp"
set "PIP_CONFIG_FILE=%CONFIG%\pip\pip.ini"
set "PIP_CACHE_DIR=%LOCAL%\cache\pip"
set "PYTHONUSERBASE=%LOCAL%\python-user"
set "PDEV_ROOT=%ROOT%"

set "SCOOP=%OPT%\scoop"
set "SCOOP_CACHE=%TMP%"
set "PYTHON_HOME=%SCOOP%\apps\python\current"
set "PYTHON_SCRIPTS=%PYTHON_HOME%\Scripts"
set "NODEJS_HOME=%SCOOP%\apps\nodejs\current"
set "VSCODE_BIN=%SCOOP%\apps\vscode\current\bin"
set "PATH=%BIN%;%PYTHON_HOME%;%PYTHON_SCRIPTS%;%NODEJS_HOME%;%VSCODE_BIN%;%SCOOP%\shims;%SystemRoot%\system32;%SystemRoot%;%SystemRoot%\System32\Wbem"

echo [PATH verification]
call :require_portable python || exit /b 1
call :require_portable pip || exit /b 1
call :require_portable node || exit /b 1
call :require_portable npm || exit /b 1
call :require_portable uv || exit /b 1
call :require_portable jq || exit /b 1
call :require_portable pandoc || exit /b 1
call :require_portable code || exit /b 1

echo.
echo [versions]
python --version
pip --version
node --version
npm --version
uv --version
jq --version
pandoc --version
code --version

echo.
echo [start vscode]
start "" code --user-data-dir "%CONFIG%\vscode\user-data" --extensions-dir "%CONFIG%\vscode\extensions"

endlocal
exit /b 0

:require_portable
for /f "delims=" %%P in ('where %1 2^>nul') do (
    echo %%P | findstr /I /B /C:"%ROOT%\\" >nul && (
        echo %%P
        exit /b 0
    )
)
echo [NG] %1 was not found under %ROOT%.
exit /b 1
