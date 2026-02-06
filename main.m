% 컨버테크세트 20251203


clear
clc, close all 

addpath('C:\Users\LuminaX_IV2\Dropbox\02. 튜브 측정\자동화코드\컨버테크+gwinstek 자동화 20260113\acquire_lock');


%% 컨버테크 애노드 파워 연결
ps_port_A    = 'COM12';
% ← 실제 포트에 맞게 수정
ps_baud_A    = 19200;     % DIP 스위치에 맞게 설정
deviceID_A   = 0;         % 장비 ID (0~31)
id_A         = bitor(uint8(0x40), uint8(deviceID_A));
maxVoltage_kV_A = 150;    % [kV] 150 kV 장비 정격
maxCurrent_A    = 0.067;  % [A]  67 mA 장비 정격


% 기존 열려있던 객체 정리 (옵션)
if exist('ps_obj_A','var') && ~isempty(ps_obj_A)
    try
        delete(ps_obj_A);   % serialport 객체 정리
    catch
    end
end
ps_obj_A = [];  % clear 대신 빈 값으로

ps_obj_A = serialport(ps_port_A, ps_baud_A, "Timeout", 0.5);
configureTerminator(ps_obj_A, 255); % 명령어 종결자 설정
flush(ps_obj_A); % 버퍼 정리

disp('컨버테크 파워서플라이 연결 완료 (150 kV 장비)');

% ========================= 장비 초기 설정 =========================
% 1) 출력 OFF (E 커맨드)
write(ps_obj_A, [0x02 id_A 'E' 0x40 0x40 0x03], "uint8");
wait_ack(ps_obj_A, 'E');
pause(0.1);

% 2) 전압 0 V 설정 (B 커맨드)
ratioV0 = 0;
SVH0 = bitor(uint8(floor(ratioV0/64)), uint8(0x40));
SVL0 = bitor(uint8(mod(ratioV0,64)),  uint8(0x40));

flush(ps_obj_A, "input");
write(ps_obj_A, [0x02 id_A 'B' SVH0 SVL0 0x03], "uint8");
wait_ack(ps_obj_A, 'B');

% 3) 전류 제한 설정 (정격 67 mA 기준, 필요시 수정)
I_limit_mA = 67;  % [mA]
ratioI_A = round(((I_limit_mA/1000) / maxCurrent_A) * 1000);  % 0~1000
ratioI_A = max(0, min(1000, ratioI_A));
SIH = bitor(uint8(floor(ratioI_A/64)), uint8(0x40));
SIL = bitor(uint8(mod(ratioI_A,64)),  uint8(0x40));

flush(ps_obj_A, "input");
write(ps_obj_A, [0x02 id_A 'C' SIH SIL 0x03], "uint8");
wait_ack(ps_obj_A, 'C');

% 4) 출력 ON (D 커맨드)
flush(ps_obj_A, "input");
pause(0.1);
write(ps_obj_A, [0x02 id_A 'D' 0x40 0x40 0x03], "uint8");
wait_ack(ps_obj_A, 'D');

disp('초기화 완료: 0 V, 전류제한 설정, HV ON');



%% Power Supply 연결 (컨버테크 RS232)

ps_port = 'COM11';       % 컨버테크 장비 연결 포트
ps_baud = 19200;          % DIP 스위치 2번 OFF → 9600bps / 광통신은 19200
deviceID = 0;            % 장비 ID 숫자 (0~31)
id = bitor(uint8(0x40), uint8(deviceID));
maxVoltage = 5000;       % 정격 전압 [V]
maxCurrent = 0.04;       % 정격 전류 [A] (예: 50 mA => 0.05)


% 기존 열려있던 객체 정리 (옵션)
if exist('ps_obj','var') && ~isempty(ps_obj)
    try
        delete(ps_obj);   % serialport 객체 정리
    catch
    end
end
ps_obj = [];  % clear 대신 빈 값으로

% 시리얼 포트 열기
ps_obj = serialport(ps_port, ps_baud, "Timeout", 1);
configureTerminator(ps_obj, 255);
flush(ps_obj);
disp('컨버테크 파워서플라이 연결 완료 (5 kV 장비)');

write(ps_obj, [0x02 id 'E' 0x40 0x40 0x03], "uint8"); % 출력 OFF
pause(0.05);

% 전압 0 V 설정 (B COMMAND)
ratioV = 0;  % 0V로
SVH = bitor(uint8(floor(ratioV/64)), uint8(0x40));
SVL = bitor(uint8(mod(ratioV,64)),  uint8(0x40));
flush(ps_obj, "input");
write(ps_obj, [0x02 id 'B' SVH SVL 0x03], "uint8"); 

% ACK 대기
wait_ack(ps_obj, 'B');

% 전류 제한 30 mA 설정 (C COMMAND, REMOTE 필수)
I_limit_mA = 40;                                   % 원하는 전류 한계
ratioI = round(((I_limit_mA/1000) / maxCurrent) * 1000);
ratioI = max(0, min(1000, ratioI));                % 0~1000 클램프
SIH = bitor(uint8(floor(ratioI/64)), uint8(0x40)); % ((r/64) | 0x40)
SIL = bitor(uint8(mod(ratioI,64)),  uint8(0x40));  % ((r%64) | 0x40)
flush(ps_obj, "input"); % 입력버퍼 지우기
write(ps_obj, [0x02 id 'C' SIH SIL 0x03], "uint8");  % C 명령 전송

% ACK 대기
wait_ack(ps_obj, 'C');

% 출력 ON (D COMMAND)
flush(ps_obj, "input");
pause(0.05);
write(ps_obj, [0x02 id 'D' 0x40 0x40 0x03], "uint8");

% ACK 대기
wait_ack(ps_obj, 'D');


disp('전류제한 30 mA 설정 → 전압 0 V 설정 → 출력 ON 완료');



%% 현재 객체 리셋
cleanup_stale_io();   % 모든 타이머/시리얼/VISA/GPIB 확실히 해제
pause(2);

%% 인터락 + HV ON 자동 시퀀스
% ardu = serialport("COM3", 9600);   % 아두이노(릴레이 컨트롤)
% CMD_RESET        = uint8(1);
% exist('ps_obj_A','var')
% CMD_START        = uint8(2);
% CMD_PING         = uint8(3);
% CMD_FORCE_CLOSE  = uint8(4);
% CMD_HV_ON_PULSE  = uint8(5);        % ★ 신규: 15–16 순간 쇼트 명령
% pause(0.05);
% 
% disp('1');
% % 1) 안전 초기화 → 인터락 Open
% write(ardu, CMD_RESET, "uint8");
% pause(1);
% 
% % 2) 인터락 Close 유지(모니터링 없이)
% write(ardu, CMD_FORCE_CLOSE, "uint8");
% pause(1);
% disp('2');
% 
% % 3) HV ON 트리거(15–16 순간 쇼트)
% pulse_ms  = uint16(1000);                   % 네가 테스트한 0.5초
% payload   = typecast(pulse_ms,'uint8');    % [lo hi]
% try
%     write(ardu, [CMD_HV_ON_PULSE, payload], "uint8");
% catch
%     % 펌웨어가 길이 인자를 안 받는 옛 버전이면 명령만 보냄
%     write(ardu, CMD_HV_ON_PULSE, "uint8");
% end
% pause(5);  % 내부가 켜질 시간
% disp('3');
% disp('✅ HV ON 트리거 완료 — 다음 단계로 진행합니다.');
% 
% % 4) 이후부터는 기존 로직대로 모니터링 시작이 필요하면 START+PING 사용
% write(ardu, CMD_START, "uint8");   % 모니터링 시작(핑 없으면 Open으로 Fail-safe)

% 전류특성
path1 = 'C:\Users\LuminaX_IV2\Dropbox\02. 튜브 측정\튜브측정기록\#37-5 20260129 에미터테스트\260205 P-6\전류특성';
% 내전압특성
path2 = 'C:\Users\LuminaX_IV2\Dropbox\02. 튜브 측정\튜브측정기록\#40-3_20251107 5.5kW 30%\260203 140kV 내전압';
% 에미터특성
path3 = 'C:\Users\LuminaX_IV2\Dropbox\02. 튜브 측정\튜브측정기록\#27-1_260129 V-10v\20260202 140kV 내전압 전후 에미터특성';

% 에이징
path100 = 'C:\Users\LuminaX_IV2\Dropbox\02. 튜브 측정\튜브측정기록\#37-5 20260206 P-6\260205 P-6\전류전압특성';

%% 시퀀스 내 입력값 

a=1;
configs(a).spellman_voltages           = [10 20 30];            % 애노드 전압 배열
configs(a).target_currents             = [5 10 20 30 35];                   % 전류 배열
configs(a).increment_kV                = 5;                     % 스펠만 증가 범위
configs(a).hold_time                   = 5;                     % 전류 도달 후 on time 지속 시간
configs(a).num_cycles                  = 5;                     % 반복 횟수
configs(a).rest_time                   = 20;                    % 반복 간 쉬는시간
configs(a).duty                        = 10;                    % 현재 듀티
configs(a).ps_initial_voltage          = 0;
configs(a).kV_test                     = 0;                     % 내전압 테스트 유무 (1:유 0:무)
configs(a).hold_time_kV                = 0;                     % 내전압 테스트 시 고전압 지속시간
configs(a).function_out                = 1;                     % 함수발생기 on:1 off:0
configs(a).freq                        = 1000;                  % 함수발생기 주파수
configs(a).save_path                   = path1;

%% === 실행 구간 설정 (유동적으로 변경 가능) ===
MAX_ARC_ERRORS   = 10;   % ARC로 인한 최대 허용 중단 횟수
MAX_COMM_ERRORS  = 1;   % 통신/코드 에러 최대 허용 횟수
STEP_BACK_N = 0;   % ← 아킹 시 몇 스텝 뒤로 물릴지(1~2 추천)
%% === 실행 구간 ===
RUN_START = 1;
RUN_END   = 1;


if isappdata(0,'RESTART_FROM')
    RUN_START = getappdata(0,'RESTART_FROM');
    rmappdata(0,'RESTART_FROM');
end

% 전역 카운터 초기화 (없을 때만)
if ~isappdata(0,'ARC_ERROR_COUNT')
    setappdata(0,'ARC_ERROR_COUNT', 0);
end
if ~isappdata(0,'COMM_ERROR_COUNT')
    setappdata(0,'COMM_ERROR_COUNT', 0);
end

%% === 메인 루프 ===
for i = RUN_START:RUN_END
    fprintf('\n=== %d 번째 실험 시작 ===\n', i);

    try
        % [abortAll, fail_reason] = my_experiment(configs(i), ardu, CMD_PING);
        [abortAll, fail_reason] = my_experiment(configs(i));

        % ---- 정상 종료(예외 없이 try 통과) ----
        % 다음 a로 넘어갈 때는 (V,I) 재시작 포인터 초기화
        if isappdata(0,'START_PAIR_IDX'), rmappdata(0,'START_PAIR_IDX'); end
        if isappdata(0,'LAST_PAIR_IDX'),  rmappdata(0,'LAST_PAIR_IDX');  end
        fprintf('=== %d 번째 실험 종료 ===\n', i);

    catch ME
        % 공통 정리 (타이머/시리얼 등 해제)
        cleanup_stale_io();

     

        % ===== ABORT(ARC/INTERLOCK/안전 중단) 계열 처리 =====
        if startsWith(ME.identifier, "ABORT:")
            reason = string(erase(ME.identifier, "ABORT:"));   % "ARC", "INTERLOCK", "GATE_OVER_V" 등

            % 메일 제목/본문 작성
            switch reason
               case "GATE_OVER_V"
                    subject = sprintf('⚠️ MATLAB 실험 %d 게이트 과전압 중단', i);
                    message = sprintf('실험 %d 도중 게이트 과전압으로 중단되었습니다.', i);
                otherwise
                    % 기본: ARC
                    subject = sprintf('⚠️ MATLAB 실험 %d ARC 중단 발생', i);
                    message = sprintf('실험 %d 도중 ARC 감지로 중단되었습니다.', i);
            end

            recipients = {'rlatmdxo2005@naver.com'};
            sendErrorMail('rlatmdxo2005@naver.com','5MEYT3W57W4X', recipients, subject, message);

            % ---- (V,I) 재시작 위치 계산: 최근 진행 위치에서 STEP_BACK_N만큼 뒤로 ----
            lastPair = 1;
            if isappdata(0,'LAST_PAIR_IDX'), lastPair = getappdata(0,'LAST_PAIR_IDX'); end
            newStart = max(1, lastPair - STEP_BACK_N);
            setappdata(0,'START_PAIR_IDX', newStart);   % 다음 실행에서 여기부터
            setappdata(0,'RESTART_FROM', i);            % 같은 a에서 재시작

            fprintf('\n⚠️ %s 중단 → %d스텝 뒤로 (%d→%d) 재시작 예정\n', reason, STEP_BACK_N, lastPair, newStart);

            % ---- ARC/INTERLOCK/GATE_OVER_V 등 “안전 중단” 카운트 증가 ----
            arcCount = getappdata(0,'ARC_ERROR_COUNT') + 1;
            setappdata(0,'ARC_ERROR_COUNT', arcCount);

            if arcCount >= MAX_ARC_ERRORS
                fprintf('\n🚨 중단 누적 %d회 → 전체 종료\n', arcCount);
                subject = sprintf('🚨 중단 누적 %d회 초과, 전체 종료', arcCount);
                message = sprintf('중단이 %d회 누적되어 전체 실행이 종료되었습니다. (마지막: %s)', arcCount, reason);
                sendErrorMail('rlatmdxo2005@naver.com','5MEYT3W57W4X', recipients, subject, message);
                return;
            end

            fprintf('\n⚠️ %s 중단 → 30초 후 main 재실행 (%d/%d)\n', reason, arcCount, MAX_ARC_ERRORS);
            pause(30);
            try
                matlab.desktop.editor.openAndRun(mfilename('fullpath'));
            catch
                run(mfilename('fullpath'));
            end
            return;

            % ===== 일반 통신/코드 에러 처리 =====
        else
            fprintf('!!! %d 번째 실험 중 에러 발생: %s\n', i, ME.message);

            subject = sprintf('⚠️ MATLAB 실험 %d 통신/코드 오류 발생', i);
            if ~isempty(ME.stack)
                message = sprintf(['실험 %d 중 오류 발생!\n\n메시지: %s\n파일: %s\n라인: %d'], ...
                    i, ME.message, ME.stack(1).file, ME.stack(1).line);
            else
                message = sprintf(['실험 %d 중 오류 발생!\n\n메시지: %s'], i, ME.message);
            end
            recipients = {'rlatmdxo2005@naver.com'};
            sendErrorMail('rlatmdxo2005@naver.com','5MEYT3W57W4X', recipients, subject, message);

            % 통신/코드 에러 카운트 증가
            commCount = getappdata(0,'COMM_ERROR_COUNT') + 1;
            setappdata(0,'COMM_ERROR_COUNT', commCount);

            if commCount >= MAX_COMM_ERRORS
                fprintf('\n🚨 통신/코드 에러 누적 %d회 → 전체 종료\n', commCount);
                subject = sprintf('🚨 통신 에러 누적 %d회 초과, 전체 종료', commCount);
                message = sprintf('통신/코드 에러가 %d회 누적되어 전체 실행이 종료되었습니다.', commCount);
                sendErrorMail('rlatmdxo2005@naver.com','5MEYT3W57W4X', recipients, subject, message);
                return;
            end

            % 통신/코드 에러의 경우에도 (원하면) (V,I) 롤백 적용. 필요 없으면 이 블록을 지워라.
            lastPair = 1;
            if isappdata(0,'LAST_PAIR_IDX'), lastPair = getappdata(0,'LAST_PAIR_IDX'); end
            newStart = max(1, lastPair - STEP_BACK_N);
            setappdata(0,'START_PAIR_IDX', newStart);
            setappdata(0,'RESTART_FROM', i);
            fprintf('\n⚠️ 통신/코드 에러 → (V,I) %d스텝 뒤로 (%d→%d) 재시작 예정\n', STEP_BACK_N, lastPair, newStart);
            
            fprintf('\n⚠️ 통신/코드 에러 → 60초 후 main 재실행 (에러 %d/%d)\n', commCount, MAX_COMM_ERRORS);
            pause(60);
            try
                matlab.desktop.editor.openAndRun(mfilename('fullpath'));
            catch
                run(mfilename('fullpath'));
            end
            return;
        end
    end
end





%준영: 1U8UEJQ3LEY2
%승태: 5MEYT3W57W4X
