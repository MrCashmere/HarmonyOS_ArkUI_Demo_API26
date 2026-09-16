@if "%DEBUG%" == "" @echo off
@rem ##########################################################################
@rem  Hvigor 启动脚本（教学 Demo 版，Windows）
@rem
@rem  与 DevEco Studio 生成的脚本等价，差别是**优先使用 DevEco Studio 自带的
@rem  hvigor**，这样在没做过 npm install 的机器上也能直接构建。
@rem  找不到自带版本时回落 npx hvigorw。
@rem
@rem  可用环境变量：
@rem    DEVECO_SDK_HOME  —— SDK 路径（未设置时尝试常见安装位置）
@rem    NODE_HOME        —— Node 目录（未设置时用 PATH 里的 node）
@rem ##########################################################################

if "%OS%" == "Windows_NT" setlocal

set DIRNAME=%~dp0
if "%DIRNAME%" == "" set DIRNAME=.
set APP_HOME=%DIRNAME%

set NODE_EXE=node.exe

@rem --- 常见 DevEco Studio 安装位置 ---
set DEVECO_CANDIDATES="%ProgramFiles%\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" "%ProgramFiles(x86)%\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat" "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"

for %%i in (%DEVECO_CANDIDATES%) do (
  if exist %%i (
    call %%i %*
    exit /b %ERRORLEVEL%
  )
)

@rem --- 回落 npx ---
echo.
echo 未找到 DevEco Studio 自带的 hvigor，回落 npx hvigorw（首次运行会下载依赖）
echo.
call npx --yes hvigorw %*
exit /b %ERRORLEVEL%
