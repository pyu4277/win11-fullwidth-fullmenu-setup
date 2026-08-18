# windows-setup

포맷 후 다시 잡아야 하는 Windows 11 개인 설정을, **깃허브 접근만으로 골라서 적용**하는 스크립트.

의존성이 없습니다. Windows에 기본 탑재된 Windows PowerShell 5.1만 있으면 되고,
git 설치도, 클론도, 관리자 권한도 필요 없습니다.

## 쓰는 법

### 1. 한 줄 실행 (저장소가 공개일 때)

PowerShell을 열고:

```powershell
irm https://raw.githubusercontent.com/pyu4277/windows-setup/main/setup.ps1 | iex
```

메뉴가 뜨고 번호로 원하는 항목만 고르면 됩니다 (`1,2` / `a` 전체 / `q` 취소).

인자를 주고 싶으면 스크립트블록 형태로:

```powershell
# 전부 적용
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pyu4277/windows-setup/main/setup.ps1))) -All

# 특정 항목만
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pyu4277/windows-setup/main/setup.ps1))) -Only classic-context-menu

# 현재 상태만 확인
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/pyu4277/windows-setup/main/setup.ps1))) -List
```

### 2. 저장소가 비공개일 때

`raw.githubusercontent.com`은 비공개 저장소에 인증 없이 접근할 수 없습니다. 두 가지 방법:

- **GitHub 웹에서 Code → Download ZIP** → 압축 풀고 `.\setup.ps1` 실행
- **gh CLI 사용**: `gh repo clone pyu4277/windows-setup` 후 `.\setup.ps1` 실행

한 줄 실행이 편하면 저장소 설정에서 공개로 바꾸면 됩니다. 이 저장소에는
비밀값이나 개인정보가 없고 일반적인 Windows 설정 스크립트뿐입니다.

```powershell
gh repo edit pyu4277/windows-setup --visibility public --accept-visibility-change-consequences
```

### 실행 정책 때문에 막히면

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

## 포함된 항목

### `classic-context-menu` — 우클릭 시 전체 메뉴 바로 표시

Windows 11은 우클릭하면 축약된 메뉴가 나오고 **"추가 옵션 표시"** 를 한 번 더 눌러야
Everything 검색, Git Bash, 알집, 한글 문서 인쇄 같은 기존 항목이 보입니다.

모던 컨텍스트 메뉴를 담당하는 셸 확장(CLSID `{86ca1aa0-...}`)의 `InprocServer32`
기본값을 **빈 문자열**로 만들어 무력화하면, Windows 10 방식의 전체 메뉴가 처음부터 뜹니다.
`HKCU` 아래에만 키를 추가하므로 시스템 파일은 건드리지 않습니다.

참고: 새 API(IExplorerCommand)로만 등록된 일부 최신 스토어 앱 항목은 클래식 메뉴에
안 보일 수 있습니다. 실사용에서 문제가 되는 경우는 드뭅니다.

### `remove-hancom-ime` — `?` 가 `¿` 로 나오는 문제 차단

**증상:** 물음표를 쳤는데 `¿` 가 입력됨. Win+Space를 누를 때마다 재발.

**원인:** 입력기가 Microsoft 입력기와 한컴 입력기 두 개 등록되어 있고,
Win+Space가 둘 사이를 전환합니다. 한컴 입력기 상태에서는 반각 `?`(0x3F)가 아니라
**전각 `？`(U+FF1F)** 가 입력되는데, 이게 CP949로는 `A3 BF` 두 바이트라
UTF-8 환경에서 잘못 읽히면 뒷바이트 `BF`가 `¿` 로 보입니다.

**해결:** 한컴 입력기를 입력기 목록에서 제거합니다. Win+Space 자체는 Windows에
하드코딩되어 레지스트리로 끌 수 없지만, **전환할 대상이 없으면 눌러도 아무 일이 없습니다.**
전각 문자의 발생원과 전환 단축키가 동시에 해결됩니다.

한컴 오피스 프로그램 자체와 HWP 파일 작업에는 영향이 없습니다. 제거하는 것은
Windows 입력기 목록에서의 등록뿐이고, 한글에서도 Microsoft 입력기로 똑같이 입력됩니다.

> 한컴 오피스를 재설치하거나 업데이트하면 입력기가 다시 등록될 수 있습니다.
> `¿` 가 다시 보이면 이 항목을 한 번 더 실행하면 됩니다.

## 되돌리기

모든 항목은 `-Revert` 로 원상복구됩니다.

```powershell
.\setup.ps1 -Revert                              # 메뉴에서 선택
.\setup.ps1 -Only classic-context-menu -Revert   # 특정 항목만
```

`remove-hancom-ime` 되돌리기는 한컴 오피스가 설치되어 있어야 동작합니다
(입력기 DLL이 없으면 되돌릴 대상이 없으므로 중단하고 알려줍니다).

## 항목 추가하기

`setup.ps1` 의 `$Tweaks` 배열에 객체 하나를 추가하면 됩니다.
`Name` / `Title` / `Test`(적용됐는지) / `Apply` / `Revert` 다섯 개만 채우면
메뉴와 상태 표시에 자동으로 반영됩니다.

스크립트 메시지는 의도적으로 영문입니다. 이 PC는 시스템 ANSI 코드페이지가 949인데
콘솔은 65001이라, BOM 없는 UTF-8 스크립트에 한글을 넣으면 Windows PowerShell 5.1이
깨뜨립니다. 그래서 코드는 ASCII로, 설명은 이 README에 한글로 둡니다.
