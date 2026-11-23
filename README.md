# deskless

무인 객실 대여 서비스의 백엔드 · 프론트를 **쿠버네티스로 엮어 한 번에 띄우는 저장소**다. 앱 코드는 없다 — 두 저장소를 submodule 로 불러오고, 여기에는 쿠버네티스 설정만 둔다.

| 폴더 | 저장소 | 역할 |
|---|---|---|
| `backend/` | [HaSungJe/deskless-backend](https://github.com/HaSungJe/deskless-backend) (`main`) | NestJS 모노레포 — gateway · user-service · admin-service · scheduler |
| `frontend/` | [HaSungJe/deskless-frontend](https://github.com/HaSungJe/deskless-frontend) (`main`) | Next.js — 이용자 · 업체 관리자 · 관리자 화면 |

개발은 각 저장소에서 따로 하고(커밋 · 푸시도 그쪽), 이 저장소는 그 결과를 받아 "같이 띄울 백엔드 · 프론트 버전 조합" 을 커밋으로 남긴다.

## 받기

하위 저장소까지 같이 받는다.

```bash
git clone --recurse-submodules https://github.com/HaSungJe/deskless.git
```

submodule 없이 받았다면 받은 폴더에서:

```bash
git submodule update --init
```

## 하위 저장소 최신 받기

백엔드 · 프론트 저장소에 푸시한 뒤, 이 저장소에서 최신을 받고 그 조합을 커밋한다.

```bash
git submodule update --remote
git add backend frontend
git commit
```

- submodule 은 특정 커밋에 고정돼 있어 자동으로 따라가지 않는다 — 위 명령으로 받을 때만 바뀐다(따라갈 브랜치는 `.gitmodules` 의 `main`).
- `backend/` · `frontend/` 안에서는 수정 · 커밋하지 않는다. 받은 직후에는 브랜치가 아닌 커밋 위(detached HEAD)라 거기서 한 커밋은 잃어버리기 쉽다.

## 쿠버네티스 (준비 중)

방향만 정해져 있고 설정 파일은 아직 없다.

- 클러스터: 로컬은 k3d(Docker 안의 k3s) 또는 WSL2 에 k3s, 운영은 리눅스 서버에 k3s 직접 설치 — 같은 쿠버네티스(k3s)라 동작이 같다.
- 차트: Helm 차트 한 벌을 로컬 · 운영에 그대로 쓴다. 환경마다 다른 값(접속정보 · 비밀값 · 도메인 · 인스턴스 수)은 그 PC · 서버의 `.env` 하나로 정한다 — 로컬용 · 운영용 파일을 따로 두지 않는다.
- 인프라(PostgreSQL · RabbitMQ · Redis)는 앱과 따로 설치하는 묶음이다 — 관리형 서비스(RDS · Amazon MQ · ElastiCache)를 쓰는 운영에서는 설치하지 않는다.
- 이미지: 로컬은 PC 에서 빌드한 이미지(Tilt), 운영은 레지스트리의 이미지 — 각 저장소의 `Dockerfile` 을 그대로 쓴다.
