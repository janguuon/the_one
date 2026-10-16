# M5 original pixel art

이 폴더는 M5에서 게임에 연결한 원본 래스터 자산이다. EITR의 어둡고 축축한 픽셀 분위기와 묵직한 크기 대비를 참고했으며, 인물·무기·괴물·지형은 이 게임의 창세 이전 설정으로 새로 생성했다. EITR의 스프라이트, 배경, 로고, 음향을 가져오지 않았다.

제작 방식은 `imagegen` skill의 **built-in `image_gen.imagegen`**이다. CLI/API key 경로는 쓰지 않았다. 생성일은 2026-10-16. PNG 원본의 실제 알파를 보존했다. 아래 파일을 프로젝트에 복사했으며 `$CODEX_HOME` 경로에 런타임이 의존하지 않는다.

| 런타임 파일 | 원본 구성 | 실제 게임 사용 |
|---|---|---|
| `arena-primordial.png` | 불투명 1672×941 | 최근접 640×360 텍스처, 정해진 타원 가장자리에 정렬 |
| `first-human-atlas.png` | 투명 1600×1000, 8열×5행 | 48×48 셀, 약 36px 높이 인간, 40개 포즈 |
| `mujeo-atlas.png` | 투명 1744×872, 6열×3행 | 104×104 셀, 공통 몸체 18개 포즈 |
| `relics-atlas-v2.png` | 투명 2000×800, 5열×2행 | 무기 5종, 제단, 속성 4종을 40×40 셀로 로드 |

`relics-atlas.png`는 도끼가 포함됐던 초기 생성본이며 런타임에서는 사용하지 않는다. v2는 실제 설계의 창·쌍단검·묘비 망치로 순서를 수정한 선택본이다. Godot는 `load(path) as Texture2D`로 임포트 자원을 읽고 `get_image()`에서 정수 셀을 추출한다. 따라서 PCK에 원본 PNG를 따로 열어야 하는 의존성이 없다. `.png.import`는 Godot의 일반 텍스처 임포트 설정이다.

## 동작·방향 계약

인간 행은 위에서 북·북동·동·남동·남이다. 서쪽 3방향은 동쪽 원본을 반전한다. 열은 대기·왼발 이동·오른발 이동·공격 준비·실행·회복·회피·피격이다. 무기는 별도 레이어에서 같은 조준 방향으로 돌린다. 바닥 발점은 원본 셀의 `(24,42)`이며 시각 높이가 실제 지면 좌표를 바꾸지 않는다. 이동은 7틱마다 보폭을 교체하고, 공격의 세 포즈는 해당 무기의 실제 준비·실행·회복 시간을 따른다. 회피는 작은 몸체 포즈를 실제 회피 틱 동안 회전시킨다. 사망 후에는 전투 종료 뒤의 UI 시간으로 0.5초 쓰러짐을 재생한다.

창은 공격 시작 때 고정한 조준 방향을 유지하며 손과 함께 직선으로 전진하고, 망치는 위로 들었다가 조준한 충돌점 방향으로 내려친다. 검·쌍단검·사슬은 휘두르는 궤적을 쓴다. 효과 줄이기는 피격 밝기 깜박임·회피 잔상·사망 파편을 끄고 보스의 장식 박동을 정지한다. 실제 위험 표식과 속성 도형은 계속 표시한다.

보스 행은 정면·측면·후면이며 열은 대기·숨쉬기·준비·실행·회복·붕괴다. 원본 몸체를 모든 페이즈에서 재사용하고 P2 서리 테두리, P3 흉부 박동, P4 팔/몸의 잔향, P5 뒤편에 멈춰 있는 거대한 본체를 겹친다. 보스의 공격 판정은 큰 팔 그림을 따라 새로 만들지 않는다. 위험 예고·피해는 기존의 동일한 `CombatGeometry` 데이터를 계속 사용한다.

속성은 화염의 갈라진 삼각형, 서리의 육각형, 번개의 지그재그, 공허의 빈 원이다. 적의 바닥 예고와 구별되도록 획득물은 지면 그림자 위에 떠서 움직인다. 장식과 배우의 렌더링은 전투 상태를 변경하거나 게임의 난수 스트림을 사용하지 않는다.

## 생성 프롬프트와 출처

생성 도구가 저장한 원본은 아래 디렉터리에 있었다. 선택본은 위 파일명으로 복사했고 원본은 삭제하지 않았다.

`C:/Users/오장원/.codex/generated_images/01a14391-0ae2-74f1-899d-8b83a3f04329/`

### 경기장 — `exec-0ff80b33-8e16-4ae1-bd08-0fac97b56797.png`

> Use case: stylized-concept. Asset type: actual production raster pixel-art floor/background for a 640×360 dark 2D boss-raid game, not a mockup. Create an original 16:9 orthographic oblique top-down arena image, no people, no monsters, no weapons, no UI and absolutely no text. Pixel-art medium with crisp square pixel clusters, limited dark teal, coal, slate and ash palette, very subdued warm ember specks. EITR's damp, somber and weighty pixel atmosphere is a mood reference only: invent a primordial arena without Norse symbols or copied designs. Composition is essential: frame a single ellipse of playable cracked ash-stone floor, centered at x50%, y51.1%, horizontal radius40.625% of canvas and vertical radius35%; outer edge at x9.375% and90.625%, y16.1% and86.1%. The entire ellipse is flat walkable ground and must remain unobstructed and readable; no pillars or rocks inside. A thin broken double rim of black bones and basalt teeth outlines the ellipse. Beyond it, opaque black teal void, faint hanging roots and distant fossil forms. Top14% and bottom12% remain nearly black for in-game HUD. The floor should be low contrast ash-charcoal, sparse thin teal-grey cracks, worn shallow concentric age rings, small reflective damp patches; center must be quiet and lower contrast than the rim so enemies and light attack telegraphs stand out. Produce clean game background only with a controlled pixel grid equivalent to640×360, preferably rendered exactly1280×720 with each logical pixel2×2. No smooth painting, no bloom, no gradients, no lettering, no watermark, no embedded actors, no altar decorations (altars are separate runtime sprites).

### 최초의 인간 — `exec-c9a2600e-fe2c-423e-acbc-fede961c63e0.png`

> Use case: stylized-concept. Asset type: transparent production sprite atlas for an original 640×360 pixel-art boss raid game. Exactly 8 columns by 5 rows, 40 equal square cells, no extra objects or labels, completely transparent background, even invisible cell grid. Each cell equal128×128 pixels in a1024×640 canvas. Every sprite fits inside its cell with at least20 pixels clear padding, grounded feet centered at x64,y110 inside each cell. A tiny original first human, androgynous pale ash skin, short dark hair, tattered grey linen shroud, burnt charcoal leg wraps, one dim orange ember in chest. No helmet, no horn, no copied character, no weapon: weapons are separately rendered. Crisp detailed dark fantasy hand-made pixel clusters, minimal 12-color charcoal/ash/cream/teal palette plus single amber ember; crisp2×2 pixels (effectively512×320 atlas). Body height68pixels (~34 logical pixels), width34pixels. Identical design and dimensions throughout. Direction rows, top to bottom: row1 facing north(back), row2 north-east(back three quarter), row3 east(profile), row4 south-east(front three quarter), row5 south(front). Pose columns left to right: 1 idle upright low arm, 2 walk step with left leg front, 3 walk step with right leg front, 4 attack windup empty right hand drawn back, 5 attack release empty right hand thrust forward, 6 recover low arms lean forward, 7 dodge compact rolling/crouching silhouette, 8 hurt stagger back. Deliberately maintain same reference footpoint and same facing for each row. No text, no frame borders, no backdrop, no shadows cast outside cells, no antialiasing, no smooth painting, no glow halo, no color grid. Human must remain recognizable at final24×40 game pixels.

### 무저 — `exec-ddf14c65-301a-471e-8002-2445c001265a.png`

> Use case: stylized-concept. Asset type: transparent production sprite atlas, original pixel-art primordial boss for a640×360 2D game. Exact6 columns by3 rows,18 equal square cells in a1536×768 canvas, eachcell256×256. Perfectly transparent background; no labels, no frame borders, no shadows outside cells. Each sprite fits with20px padding and feet/reference point at cell x128,y230. The original creature is named The Depth: tall folded black bone being, head is a narrow faceless skull sliver, oversized ribs encircle a conspicuous EMPTY DARK HOLE in its chest (hole must be transparent), segmented long arms end in four bone blades, charcoal rag/shadow legs, thin ash grey rims catching damp teal light. No horns, no crown, no armor, no humanoid warrior design; monstrous but readable. Black bone, grey ivory, and dark petrol palette, only tiny cold grey joint lights. Rough high contrast32bit pixel art with explicit crisp2×2/3×3 pixel clusters and designed silhouette, not smooth painting. Standardheight196pixels (~98gamepixels), normalwidth140pixels. Direction rows: row1 front facing down, row2 east profile, row3 back facing up. Columns:1 idle folded arms and chest hole visible,2 idle breath ribs open wider,3 attack windup one folded arm raised back,4 attack release arm extended forward with bone claw,5 recover crouch long arm near ground,6 collapse/death broken knees and drooping arms. Each row keep exact facing and body proportions/recognizable empty heart. The boss is primordial evil, before mythology. Dark damp weighty fantasy pixel atmosphere, not a copy of any existing game. No text, no UI, no backdrop, no glow halo, no floor, no antialiasing.

### 제단·무기·기운 — 초기 `exec-fa2e41d5-ae3d-45d2-a408-8610b92c2627.png`

> Use case: stylized-concept. Asset type: production transparent pixelart prop atlas for a dark original primordial bossraid game. Exact5columns by2rows,in a1000×400 canvas, squarecells200×200. Transparentbackground, eachobjectisolatedandcenteredwithinitscell, generous24pxpadding,nolabels,noframeborders,noshadowsoutsidecells. Crispsquarepixelclustersandeffectively500×200resolution (2×2pixels). Charcoal/ash/ivory/petrolpalette, warmamberonlyforflame,spectraliceblueforfrost,yellowwhiteforlightning, mutedpurpleforvoid. Row1containsfiveclearlydifferentsingleweapons,diagonalfrombottomlefttotopright,fullobjectlength140pixels:simplewornashironstraightonehandedsword,widecrackedstoneheavyaxe,longashenbone-spear,two pairedcurvedshortdaggers, barbedchainwhipcurledinaclearSsilhouette. Row2: column1lowstonealtarwith a recessedemptysocketandblackbonepedestal viewed obliquelyfromabove; column2firepickupafloatingglowingORANGECRACKEDTRIANGLEofemberfragments;column3frostpickupawhiteblueHEXAGONwithsharpchippededges;column4lightningpickupayellowivoryZIGZAGspark;column5voidpickupapurpleEMPTYRINGwithdarkfloatingfragmentsandTRANSPARENThole. Eachpickupheight80pixels,preciseshapesandpixelrimglowin2or3steps(noblur). Thesearenativesprites,nonUIicons,nobackdrop,nofloor,norunes,noexistingbrand,nolettering,noantialiasing,no smooth vector linework.

### 위 자산의 실제 무기 순서 수정 — `exec-10af47ea-53b4-470c-a252-799f0220139b.png`

`referenced_image_paths=[assets/art/relics-atlas.png]`, `transparent_background=true`로 기존 PNG를 먼저 확인한 뒤 수정했다.

> Edit this transparent production pixelart sprite atlas. Keep the exact5columns×2rowslayout, exact transparentbackground, samepixelstyle, objectpaddingsandbottomrowunaltered. Thetoprowmustmatchthefiveactualweapons inthisorder: column1 keep sword; column2 replaceaxe with a long slender barbedbone-SPEAR, sharpnarrowtipandlongshaft, bottomlefttotopright; column3 replaceexistingspear with TWO shortcurvedDAGGERS sidebyside; column4 replacetwodaggers witha TOMBSTONE HAMMER: massive rectangular crackedgravestonehead on a shortblackwoodshaft, no axeedge, bottomlefttotopright; column5keepchain. The weaponshapes mustremainverydistinctat24gamepixels: sword, spear, daggers, RECTANGULARHAMMER, chain. Bottomrow altar/firetriangle/frosthexagon/lightningzigzag/voidring stays EXACTLYTHESAME. Noaddedlabels,no text,no cellgrid, no floor,noframeborder. Preservealpha.

## 검증

`tests/art_tests.gd`는 이미지 로드·각 셀의 실제 알파·모든 프레임 내용·8방향 매핑·공격 준비/실행/회복·이동 프레임·회피·사망·보스 자세·5무기 타이밍·난수 무변경을 확인한다. 창의 방향/실제 직선 판정 일치와 효과 줄이기, 최근접 축소 뒤에도 각 행의 걷기/숨쉬기 픽셀이 실제로 달라지는 검사까지 **290 checks / 0 failures**를 통과했다.

`tests/art_render_tests.gd`는 **실제 그래픽 렌더러에서만** 실행하는 회귀 검사다. 음수 `draw_texture_rect` 너비가 배우를 발점에서 한 셀만큼 밀어낸 문제를 발견해, 고정된 양수 사각형에 로컬 transform 반사를 적용하도록 수정했다. 실제 프레임버퍼를 읽어 인간 5뷰·보스 3뷰의 반전 전후 경계·가시 픽셀 중심·픽셀 수를 비교한다. Intel Arc OpenGL에서 **32 checks / 0 failures**를 통과했다. 이 검사는 headless 모드에서는 통과 처리하지 않는다.

실제 OpenGL 게임 창에서 P4의 배우·기운 제단·동심원 예고를 확인한 캡처는 `.tools/captures/m5-art-p4.png`다. 큰 화면에서의 사람이 직접 하는 전체 완주와 아트 가독성 관찰은 별도 수동 검증이 필요하다.
