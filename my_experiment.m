function [abortAll, fail_reason] = my_experiment(cfg, ardu, CMD_PING)


%% 전체 시퀀스 자동화



close all;




%% 완전 FAIL 기준 (코드종료)
% fail_trans_threshold = 60;    % [%] 투과율 하한 / NaN 일떄 처리하는 과정 추가해야함


%% 초기 셋팅 입력값

%변동값

spellman_voltages           = cfg.spellman_voltages;
target_currents             = cfg.target_currents;
hold_time                   = cfg.hold_time;
num_cycles                  = cfg.num_cycles;
rest_time                   = cfg.rest_time;
duty                        = cfg.duty;
kV_test                     = cfg.kV_test;
hold_time_kV                = cfg.hold_time_kV; 
save_path                   = cfg.save_path;
function_out                = cfg.function_out;
freq                        = cfg.freq;
ps_initial_voltage          = cfg.ps_initial_voltage;  
increment_kV                = cfg.increment_kV;  

%고정값
% ps_initial_voltage          = 0;  
fail_gate_v_limit           = 4200;
ps_voltage_limit            = 4300;       
ps_voltage_range            = 60; 
initial_kV                  = 0;                 
% increment_kV                = 5;              
increment_time              = 0.5; 
step_interval               = 0.4;           
step_interval_hold          = 0.5;
step_interval_off           = 0.5;
num_last_rows               = 5;  

disp('123')


%% 컨버테크 애노드 파워 연결
ps_port_A    = 'COM12';   % ← 실제 포트에 맞게 수정
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
configureTerminator(ps_obj_A, 255);
flush(ps_obj_A);

disp('컨버테크 파워서플라이 연결 완료 (150 kV 장비)');
setappdata(0,'PS_OBJ_A_HANDLE', ps_obj_A);


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

% ARC(아킹) 판정 기준
dv_threshold_kV_A = 20;   % [V] |설정전압 - 측정전압| ≥ 이 값이면 ARC로 판단

%% 게이트 Power Supply 연결 (컨버테크 RS232)

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
ps_obj = serialport(ps_port, ps_baud, "Timeout", 0.5);
configureTerminator(ps_obj, 255);
flush(ps_obj);
disp('컨버테크 파워서플라이 연결 완료');
setappdata(0,'PS_OBJ_HANDLE', ps_obj);


%초기설정
write(ps_obj, [0x02 id 'E' 0x40 0x40 0x03], "uint8"); % 출력 OFF
wait_ack(ps_obj, 'E');

% 전압 0 V 설정 (B COMMAND)
ratioV = 0;  % 0V로
SVH = bitor(uint8(floor(ratioV/64)), uint8(0x40));
SVL = bitor(uint8(mod(ratioV,64)),  uint8(0x40));

write(ps_obj, [0x02 id 'B' SVH SVL 0x03], "uint8"); 
wait_ack(ps_obj, 'B');

% 전류 제한 40 mA 설정 (C COMMAND, REMOTE 필수)
I_limit_mA = 40;                                   % 원하는 전류 한계
ratioI = round(((I_limit_mA/1000) / maxCurrent) * 1000);
ratioI = max(0, min(1000, ratioI));                % 0~1000 클램프
SIH = bitor(uint8(floor(ratioI/64)), uint8(0x40)); % ((r/64) | 0x40)
SIL = bitor(uint8(mod(ratioI,64)),  uint8(0x40));  % ((r%64) | 0x40)

write(ps_obj, [0x02 id 'C' SIH SIL 0x03], "uint8");  % C 명령 전송
wait_ack(ps_obj, 'C');

% 출력 ON (D COMMAND)

write(ps_obj, [0x02 id 'D' 0x40 0x40 0x03], "uint8");
wait_ack(ps_obj, 'D');


disp('전류제한 30 mA 설정 → 전압 0 V 설정 → 출력 ON 완료');



% %% Multimeter 연결 설정
% % Find a GPIB object.
% % multi_obj = instrfind('Type', 'gpib', 'BoardIndex', 0, 'PrimaryAddress', 18, 'Tag', '');
% % if isempty(multi_obj)
% %     multi_obj = gpib('NI', 0, 18);
% % else
% %     fclose(multi_obj);
% %     multi_obj = multi_obj(1);
% % end
% % pause(0.05);
% % fopen(multi_obj);
% 
% multi_obj = instrfind('Type', 'gpib', 'BoardIndex', 0, 'PrimaryAddress', 18, 'Tag', '');
% 
% % Create the GPIB object if it does not exist
% % otherwise use the object that was found.
% if isempty(multi_obj)
%     multi_obj = gpib('NI', 0, 18);
% else
%     fclose(multi_obj);
%     multi_obj = multi_obj(1);
% end
% 
% % Connect to instrument object, obj1.
% fopen(multi_obj);
% 
% Spellman Voltage Ramp-Up Started
% pause(0.05);
% 
% fprintf(multi_obj, "*RST"); %초기화
% pause(0.1);% 리셋
% fprintf(multi_obj, 'FUNC "VOLT:DC"'); 
% pause(0.1);% DC 전압 측정 모드
% fprintf(multi_obj, 'VOLT:DC:RANG 1');  % 2rk 10V 1이 1V
% pause(0.1);% 범위 설정
% fprintf(multi_obj, 'FORM:ELEM READ');       % 측정값만 반환하도록 설정
% pause(0.1);
% fprintf(multi_obj, 'TRIG:SOUR IMM'); % 연속측정모드
% pause(0.1);% 자동 트리거
% fprintf(multi_obj, 'TRIG:COUN INF'); 
% pause(0.1);% 무한 트리거 설정
% fprintf(multi_obj, 'INIT');  % 측정 시작
% pause(0.1);


%% 함수발생기 AFG2005 연결
fun_name = "COM9";  % <- 사용하는 포트로 변경
fun_baud = 9600;
fun_obj = serialport(fun_name, fun_baud, "Timeout", 0.3);

flush(fun_obj);
disp('함수발생기 연결 완료');

writeline(fun_obj, 'SOUR1:FUNC SQU'); 
pause(0.05); % 파형을 Pulse로 설정
writeline(fun_obj, sprintf('SOUR1:FREQ %e', freq)); 
pause(0.05);% 주파수 설정
writeline(fun_obj, sprintf('SOUR1:SQU:DCYC %f', duty)); 
pause(0.05);% 듀티 설정
if function_out == 1
    writeline(fun_obj, 'OUTP1 ON');
    pause(0.05); % 출력 켜기
else
    writeline(fun_obj, 'OUTP1 OFF');
    pause(0.05); % 출력 끄기
end


%% 전역(appdata) 상태 초기화 — 실험 시작 시점에 1회 리셋
setappdata(0, 'RUN_T0', tic);                % 기준 시간 (실험 시작 기준)
setappdata(0, 'SERIAL_BUSY', false);         % 직렬 점유 플래그

% ARC 관련 (감지만 타이머에서 수행하므로 단순 리셋)
setappdata(0, 'ARC_DETECTED', false);        % 아킹 플래그 초기화
setappdata(0, 'ARC_DETECT_COUNT', uint32(0));% 아킹 카운트 초기화
setappdata(0, 'ARC_LAST_FRAME', "");         % 마지막 프레임 (디버깅용)

% INTERLOCK 관련 (일단 보류)
% setappdata(0, 'INTERLOCK_FAULT', false);     % 인터락 감지 리셋
% setappdata(0, 'INTERLOCK_LAST_FRAME', "");   % 디버깅용
% setappdata(0, 'INTERLOCK_FAULT_TIME', 0);    % 감지 시각 초기화
% setappdata(0, 'INTERLOCK_EXPECT', 1);        % HV ON(=1) 기대

% 저장관련
setappdata(0,'NORMAL_COMPLETION', false);


%% 실시간 그래프 초기화
figure();

subplot(5,1,1); % Anode Current 그래프
h_current = animatedline('Color','b','Marker','o','LineStyle','-');
ylabel('[mA]');
title('Anode Current');
% yticks(0:5:30);     
% ylim([0 12]); 
grid on;

subplot(5,1,2); % Anode Voltage
h_Anode_V = animatedline('Color','b','Marker','o','LineStyle','-');
ylabel('[kV]');
yticks(0:20:140);
ylim([0 140]);
title('Anode Voltage');
grid on;

subplot(5,1,3); % Gate Current 그래프
h_ps_current = animatedline('Color','r','Marker','o','LineStyle','-');
ylabel('[mA]');
title('Gate Current');
yticks(0:2:12);
ylim([0 12]);
grid on;

subplot(5,1,4); % Gate Voltage 그래프
h_voltage = animatedline('Color','r','Marker','o','LineStyle','-');
ylabel('[V]');
yticks(0:500:4000);
ylim([0 4000]);
title('Gate Voltage');
grid on;

subplot(5,1,5); % Transmission
h_Trans = animatedline('Color','g','Marker','o','LineStyle','-');
ylabel('[%]');
yticks(0:20:100);
ylim([0 100]);
title('Transmission');
grid on;

% subplot(6,1,6); 
h_Gate_DC = animatedline('Color','k','Marker','o','LineStyle','-');
% ylabel('[mA]');
% % yticks(0:20:100);     
% % ylim([0 100]);          
% title('Gate DC mA');
% grid on;

%% 로컬함수 - 컨버테크애노드 아킹 플래그 처리
    function raise_arc_flag_from_convatech(tag, dV_kV, Vset_kV, Vmeas_kV)
        % tag: "RAMP", "HOLD" 등 위치 표시용

        if ~isappdata(0,'RUN_T0')
            setappdata(0,'RUN_T0', tic);
        end
        if ~isappdata(0,'ARC_DETECT_COUNT')
            setappdata(0,'ARC_DETECT_COUNT', uint32(0));
        end

        tNow = toc(getappdata(0,'RUN_T0'));
        cnt  = getappdata(0,'ARC_DETECT_COUNT') + 1;

        setappdata(0,'ARC_DETECT_COUNT', uint32(cnt));
        setappdata(0,'ARC_DETECTED', true);

        msg = sprintf('[CONVERTECH %s] dV=%.3f kV (Vset=%.3f kV, Vmeas=%.3f kV) @ %.3f s', ...
            tag, dV_kV, Vset_kV, Vmeas_kV, tNow);
        setappdata(0,'ARC_LAST_FRAME', msg);

        fprintf('>>> ARC DETECTED #%d %s\n', cnt, msg);
    end



%% 로컬함수 - 아킹감지
    function abort_and_throw(reason)
        save_checkpoint(reason);
        do_emergency_shutdown(ps_obj_A, ps_obj);
        setappdata(0,'ARC_DETECTED', false);
        % 예: 'ABORT:ARC' / 'ABORT:INTERLOCK' / 'ABORT:GATE_OVER_V'
        throw(MException(['ABORT:' char(reason)], 'Aborted due to %s', char(reason)));
    end







% %% --- 핑 헬퍼: 아두이노 통신 끊기면 즉시 저장→셧다운→예외 전파 ---
%     function ardu_ping()
%         try
%             write(ardu, CMD_PING, "uint8");
%         catch ME
%             save_checkpoint("COMM_ERROR");
%             do_emergency_shutdown(ps_obj_A, ps_obj);   % 기존 셧다운 함수 그대로 사용
%             error('COMM_ERROR:Arduino','Arduino comm lost: %s', ME.message);  % ← main의 catch로 올라감
%         end
%     end



%% === autosave (robust) ===
% 그래프 만든 직후 1회만 등록
autosave_tag  = datestr(now,'yyyymmdd_HHMMSS');
base_autoname = fullfile(save_path, ['autosave_' autosave_tag]);

% onCleanup/콜백에서도 접근 가능하도록 appdata에 저장
setappdata(0,'AUTOSAVE_BASE', base_autoname);
setappdata(0,'AUTOSAVE_FIGH', gcf);   % 사용자가 피겨를 닫아도 나중에 체크해서 skip

% % 저장 유틸 (외부 변수 의존 X)
    function save_checkpoint(reason)
        try
            % === 정상 종료 여부 확인 ===
            if strcmpi(string(reason),'cleanup') && isappdata(0,'NORMAL_COMPLETION') ...
                    && getappdata(0,'NORMAL_COMPLETION')
                fprintf('[Autosave] cleanup skipped (normal completion)\n');
                return; % 정상 종료면 autosave 무시
            end

            % === 0) 파일 베이스명 복원 ===
            base_from_app = getappdata(0,'AUTOSAVE_BASE');
            if isempty(base_from_app)
                base_from_app = fullfile(save_path, ['autosave_' datestr(now,'yyyymmdd_HHMMSS')]);
            end

            % === 1) raw_data -> xlsx (없으면 skip) ===
            try
                if exist('raw_data','var') && ~isempty(raw_data)
                    T = cell2table(raw_data, 'VariableNames', ...
                        {'Cycle','Time','Phase','Spellman_Voltage','Target_Anode_mA', ...
                        'Gate_Voltage','Anode_Current','Gate_mA','Trans', ...
                        'Gate_MA_real','Trans_real','Gate_R','Additional_Info'});
                    xlsx_path = [char(base_from_app) '_' char(reason) '.xlsx'];
                    writetable(T, xlsx_path, 'Sheet', 1);
                    if exist('averaged_row','var') && istable(averaged_row) && height(averaged_row)>0
                        writetable(averaged_row, xlsx_path, 'Sheet', 2, 'WriteMode','append');
                    end
                end
            catch e1
                warning('[Autosave:table 실패 - %s] %s', char(reason), e1.message);
            end

            % === 2) figure -> png (닫혔거나 핸드 아니면 조용히 skip) ===
            try
                fh = [];
                if isappdata(0,'AUTOSAVE_FIGH'), fh = getappdata(0,'AUTOSAVE_FIGH'); end
                if isempty(fh), fh = get(0,'CurrentFigure'); end
                if ~isempty(fh) && isgraphics(fh)
                    png_path = [char(base_from_app) '_' char(reason) '.png'];
                    exportgraphics(fh, png_path, 'Resolution', 200);
                end
            catch e2
                warning('[Autosave:figure 실패 - %s] %s', char(reason), e2.message);
            end

            fprintf('[Autosave] %s → %s_*.{xlsx,png}\n', char(reason), char(base_from_app));
        catch e
            warning('[Autosave 실패 - %s] %s', char(reason), e.message);
        end
    end


    function cleanup_all(reason)
        % 1) 무조건 저장
        save_checkpoint(reason);

        % 2) 정상 종료면 셧다운 스킵
        if isappdata(0,'NORMAL_COMPLETION') && getappdata(0,'NORMAL_COMPLETION')
            return;
        end
        % 3) appdata에서 장비 핸들 꺼내기
        psa = [];
        psg = [];
        try
            if isappdata(0,'PS_OBJ_A_HANDLE')
                psa = getappdata(0,'PS_OBJ_A_HANDLE');
            end
            if isappdata(0,'PS_OBJ_HANDLE')
                psg = getappdata(0,'PS_OBJ_HANDLE');
            end
        catch
        end
        % 4) 셧다운 (절대 에러 던지지 않기)
        try
            do_emergency_shutdown(psa, psg);
        catch
        end
    end



% === 어떤 종료 형태라도 마지막에 한 번 저장 ===
% cleanupObj = onCleanup(@() save_checkpoint("cleanup"));
cleanupObj = onCleanup(@() cleanup_all("cleanup"));



%% 메인 루프 배열 설정
raw_data = {};
all_times = [];
all_gate_DC = [];
all_currents = [];
all_voltages = [];
all_ps_currents = [];
all_Trans = [];
averaged_row = [];
all_spellman_voltages = [];
error_log = []; 
pid_adjustment_log = []; 

start_time = tic;                      % 기준 시계 시작
setappdata(0,'RUN_T0', start_time);    % 콜백들이 공유해서 쓰도록 저장

abortAll    = false;                   % 전체 중단 플래그
fail_reason = "";                      % FAIL 사유 문자열





%% ====== DC 누설전류용 R 측정 ======
% dc_test_voltages = [50, 55, 60, 65, 70];
% dc_test_currents = [];
% fprintf('\n[Gate DC 측정] 시작: %s\n', datestr(now));
% for v = dc_test_voltages
%     fprintf(ps_obj, ['VSET ' num2str(v)]); % 전압보내기
%     pause(3.0);
%     fprintf(ps_obj, 'IOUT?'); % 전류읽기 
%     curr = str2double(fscanf(ps_obj)) * 1000;  % mA
%     dc_test_currents(end+1) = curr;
%     fprintf('[DC 측정] Gate_V: %.1f V → Gate_I: %.3f mA\n', v, curr);
% end
% fprintf(ps_obj, 'VSET 0');  % 측정 후 다시 0V로
% pause(0.5);
% % R 계산
% R_values = dc_test_voltages ./ dc_test_currents;
% R_valid = R_values(~isinf(R_values) & R_values > 0);
% R_dc = mean(R_valid);
% 
% fprintf('[DC 모델] 최종 R_dc = %.2f Ohm\n', R_dc);
R_dc =  0;

% --- PID 계수용
Kp_I_table  = [5 10 20 30 40 50];   % target_current
Kp_Kp_table = [5 4 1 1 1 1];        % 원하는 Kp 값


% ardu_ping()

% === (V, I) 재시작 컨트롤 ===
start_pair_idx = 1;
if isappdata(0,'START_PAIR_IDX')
    start_pair_idx = getappdata(0,'START_PAIR_IDX');
end
pairIdx = 0;  % (V,I) 조합 진행 카운터



% 스펠만 고전압 증가 
for spellman_voltage = spellman_voltages
    fprintf('Starting experiments with Spellman Voltage: %.1f kV\n', spellman_voltage);
  
    % ardu_ping()
% 목표전류
    for target_current = target_currents
        % ardu_ping()
        % === (V,I) 인덱스 증가 & 시작점 체크 ===
        pairIdx = pairIdx + 1;
        setappdata(0,'LAST_PAIR_IDX', pairIdx);
        if pairIdx < start_pair_idx
            fprintf('[Skip] pair #%d → %.0fkV, %.0fmA (resume from #%d)\n', ...
                pairIdx, spellman_voltage, target_current, start_pair_idx);
            continue;   % 이 조합은 건너뛰고 다음 (V,I)로
        end

    %PID
        Kp = interp1(Kp_I_table, Kp_Kp_table, target_current, 'linear', 'extrap');
        Ki = 0.013;
        Kd = 0;

        cycle_idx = 1; % 전류 바뀔때마다 사이클 초기화 
        restartCycle = false;   % ARC 시 '현 Spellman/Target에서 사이클 1부터' 재시작 지시 플래그
        while cycle_idx <= num_cycles
            % ardu_ping()
            current_kV = initial_kV;
            % spellman 전압 상승 루프
            fprintf('Cycle %d | Spellman Voltage Ramp-Up Started.\n', cycle_idx);
            

            while current_kV <= spellman_voltage % 스펠만 상승 루프 
                loop_start_time = toc(start_time);

                [tripped, reason] = handle_fault();
                if tripped
                    abort_and_throw(reason);
                end

                % ardu_ping()


                % 1) 컨버테크 애노드 전압 설정 (B 커맨드)
                ratio_setV = round((current_kV / maxVoltage_kV_A) * 1000);  % 0~1000
                ratio_setV = max(0, min(1000, ratio_setV));

                SVH = bitor(uint8(floor(ratio_setV/64)), uint8(0x40));
                SVL = bitor(uint8(mod(ratio_setV,64)),  uint8(0x40));

                frameB = [0x02 id_A 'B' SVH SVL 0x03];
                send_with_ack_retry(ps_obj_A, frameB, 'B', 0.3, 1);  % ACK 0.3초, 재시도 1회

                flush(ps_obj_A, "input");
                write(ps_obj_A, [0x02 id_A 'A' 0x40 0x40 0x03], "uint8");
                try
                    data = read(ps_obj_A, 15, "uint8");
                catch ME
                    warning('RAMP: 컨버테크 A커맨드 read 타임아웃: %s', ME.message);
                    continue;
                end

                if data(1) ~= 0x02
                    warning('RAMP: A 프레임 동기화 깨짐. 첫 바이트=0x%02X', data(1));
                    continue;
                end


                % --- 측정 전압 (kV) ---
                MVH = double(bitand(data(2), 0x3F));
                MVL = double(bitand(data(3), 0x3F));
                ratioV_meas      = MVH*64 + MVL;                         % 0~1000
                V_meas_kV        = ratioV_meas * maxVoltage_kV_A / 1000; % [kV]
                current_kV_output = V_meas_kV;                           % 측정 애노드 전압

                % --- 측정 전류 (mA) ---
                MIH = double(bitand(data(4), 0x3F));
                MIL = double(bitand(data(5), 0x3F));
                ratioI_meas   = MIH*64 + MIL;      % 0~1000
                

                ratioI_meas = max(0, min(1000, ratioI_meas));
                I_meas_mA_A    = maxCurrent_A * ratioI_meas;       % [A]                      % [mA]
                % 여기서는 "지금 측정된 애노드 전류"를 Anode_mA_offset에 매핑
                Anode_mA_offset = I_meas_mA_A;

                % --- 설정 전압 (kV, 장비 내부값) ---
                SVH_r = double(bitand(data(6), 0x3F));
                SVL_r = double(bitand(data(7), 0x3F));
                ratioV_set     = SVH_r*64 + SVL_r;                       % 0~1000
                V_set_read_kV  = ratioV_set * maxVoltage_kV_A / 1000;    % [kV]

                % --- dV 계산 (설정 - 측정) ---
                dV_kV_ramp = V_set_read_kV - current_kV_output;          % [kV]

                % === ARC 체크 ===
                if abs(dV_kV_ramp) >= dv_threshold_kV_A
                    fprintf('\n!!! ARC DETECTED DURING RAMP: dV = %.2f kV → ARC 플래그 세팅 !!!\n', dV_kV_ramp);

                    % Spellman 타이머 대신: ARC 플래그만 올림
                    raise_arc_flag_from_convatech("RAMP", ...
                        dV_kV_ramp, ...
                        V_set_read_kV, ...
                        current_kV_output);

                    % 이 루프는 종료 → 다음 반복에서 handle_fault()가 캐치
                    break;
                end

                % % % 에노드전류 읽기 - 미세 누설전류 확인용이라 멀티미터로 읽음
                % fprintf(multi_obj, ':READ?');
                % measured_voltage = str2double(fscanf(multi_obj));
                % Anode_mA_offset = round(measured_voltage*6.7*100/duty, 4); % 지금 전계방출 전이라 오프셋으로 저장


                % % 데이터 기록
                all_times = [all_times, loop_start_time];
                all_currents = [all_currents, Anode_mA_offset];
                all_voltages = [all_voltages, 0];
                all_ps_currents = [all_ps_currents, 0];
                all_Trans = [all_Trans, 0];
                all_spellman_voltages = [all_spellman_voltages, current_kV];
                all_gate_DC = [all_gate_DC, 0];

                addpoints(h_current, loop_start_time, Anode_mA_offset);
                addpoints(h_voltage, loop_start_time, 0);
                addpoints(h_ps_current, loop_start_time, 0);
                addpoints(h_Anode_V, loop_start_time, current_kV);
                addpoints(h_Trans, loop_start_time, 0);
                addpoints(h_Gate_DC, loop_start_time, 0);

               

                drawnow limitrate;

                % 상태 출력
                fprintf('Cycle %d | Time: %.1f s | Spellman Voltage: %.1f kV | Anode offset: %.4f mA.\n', cycle_idx, loop_start_time, current_kV, Anode_mA_offset );

                % Raw Data 저장 (Ramp-Up 단계)
                raw_data = [raw_data; {cycle_idx, loop_start_time, "Ramp-Up", current_kV, target_current, 0, Anode_mA_offset, 0, 0, 0, 0, 0 []}];


                % 스펠만 전압 홀드 (내전압테스트)
                if current_kV == spellman_voltage
                    disp(['Spellman Voltage Set to ' num2str(current_kV) ' kV']);

                    % Spellman 전압 도달 후 일정 시간 유지 (hold_time_kV 적용)
                    if hold_time_kV > 0
                        hold_start_time = tic; % 타이머 시작
                        while toc(hold_start_time) < hold_time_kV
                            
                            
                          
                            loop_start_time = toc(start_time);

                            [tripped, reason] = handle_fault();
                            if tripped
                                abort_and_throw(reason);
                            end


                            % ardu_ping()


                            %% === 컨버테크 애노드 전압 설정 + 상태 읽기 + ARC 체크 (RAMP 구간) ===

                            % 2) 상태 읽기 (A 커맨드: blocking read 사용)
                            flush(ps_obj_A, "input");
                            write(ps_obj_A, [0x02 id_A 'A' 0x40 0x40 0x03], "uint8");
                            try
                                data = read(ps_obj_A, 15, "uint8");
                            catch ME
                                warning('RAMP: 컨버테크 A커맨드 read 타임아웃: %s', ME.message);
                                continue;
                            end

                            if data(1) ~= 0x02
                                warning('RAMP: A 프레임 동기화 깨짐. 첫 바이트=0x%02X', data(1));
                                continue;
                            end

                            % --- 측정 전압 (kV) ---
                            MVH = double(bitand(data(2), 0x3F));
                            MVL = double(bitand(data(3), 0x3F));
                            ratioV_meas      = MVH*64 + MVL;                         % 0~1000
                            V_meas_kV        = ratioV_meas * maxVoltage_kV_A / 1000; % [kV]
                            current_kV_output = V_meas_kV;                           % 측정 애노드 전압

                            % --- 측정 전류 (mA) ---
                            MIH = double(bitand(data(4), 0x3F));
                            MIL = double(bitand(data(5), 0x3F));
                            ratioI_meas   = MIH*64 + MIL;                            % 0~1000
                            ratioI_meas = max(0, min(1000, ratioI_meas));
                            I_meas_mA_A    = maxCurrent_A * ratioI_meas;       % [A]
                            % 여기서는 "지금 측정된 애노드 전류"를 Anode_mA_offset에 매핑
                            Anode_mA_offset = I_meas_mA_A;

                            % --- 설정 전압 (kV, 장비 내부값) ---
                            SVH_r = double(bitand(data(6), 0x3F));
                            SVL_r = double(bitand(data(7), 0x3F));
                            ratioV_set     = SVH_r*64 + SVL_r;                       % 0~1000
                            V_set_read_kV  = ratioV_set * maxVoltage_kV_A / 1000;    % [kV]

                            % --- dV 계산 (설정 - 측정) ---
                            dV_kV_ramp = V_set_read_kV - current_kV_output;          % [kV]

                            % === ARC 체크 ===
                            if abs(dV_kV_ramp) >= dv_threshold_kV_A
                                fprintf('\n!!! ARC DETECTED DURING RAMP: dV = %.2f kV → ARC 플래그 세팅 !!!\n', dV_kV_ramp);

                                % Spellman 타이머 대신: ARC 플래그만 올림
                                raise_arc_flag_from_convatech("RAMP", ...
                                    dV_kV_ramp, ...
                                    V_set_read_kV, ...
                                    current_kV_output);

                                % 이 루프는 종료 → 다음 반복에서 handle_fault()가 캐치
                                break;
                            end

                            % % % 에노드전류 읽기 - 미세 누설전류 확인용이라 멀티미터로 읽음
                            % fprintf(multi_obj, ':READ?');
                            % measured_voltage = str2double(fscanf(multi_obj));
                            % Anode_mA_offset = round(measured_voltage*6.7*100/duty, 4); % 지금 전계방출 전이라 오프셋으로 저장



                            % % 데이터 기록
                            all_times = [all_times, loop_start_time];
                            all_currents = [all_currents, Anode_mA_offset];
                            all_voltages = [all_voltages, 0];
                            all_ps_currents = [all_ps_currents, 0];
                            all_Trans = [all_Trans, 0];
                            all_spellman_voltages = [all_spellman_voltages, spellman_voltage];
                            all_gate_DC = [all_gate_DC, 0];

                            addpoints(h_current, loop_start_time, Anode_mA_offset);
                            addpoints(h_voltage, loop_start_time, 0);
                            addpoints(h_ps_current, loop_start_time, 0);
                            addpoints(h_Anode_V, loop_start_time, spellman_voltage);
                            addpoints(h_Trans, loop_start_time, 0);
                            addpoints(h_Gate_DC, loop_start_time, 0);
                           
                          
                            drawnow limitrate;

                            % 상태 출력
                            fprintf('Cycle %d | Time: %.1f s | Spellman Voltage: %.1f kV | Anode offset: %.4f mA.\n', cycle_idx, loop_start_time, current_kV, Anode_mA_offset );



                            % 상태 출력
                            % fprintf('Cycle %d | Time: %.1f s | Spellman Voltage: %.1f kV.\n', cycle_idx, loop_start_time, current_kV);

                            % Raw Data 저장 (Ramp-Up 단계)

                            raw_data = [raw_data; {cycle_idx, loop_start_time, "Spellman-Hold", spellman_voltage, target_current, 0, Anode_mA_offset, 0, 0, 0, 0, 0 []}];

                            % 주기적 대기 (step_interval 적용)
                            pause(step_interval);
                        end
                        if restartCycle
                            restartCycle = false; continue;
                        end

                    end

                    break; % 목표 전압 도달 후 Hold 완료되면 루프 종료
                end

                % 전압 상승
                current_kV = min(current_kV + increment_kV, spellman_voltage);

                % 주기 유지
                pause(max(0, increment_time - mod(toc(start_time), increment_time)));

            end

            % 램프업이 ARC로 끊겼으면 바로 사이클 처음으로
          
            if restartCycle
                restartCycle = false;
                continue;   % while cycle_idx 맨 위로 (즉, 램프업부터 다시)
                
            end

            fprintf('Cycle %d | Spellman Voltage Ramp-Up Completed.\n', cycle_idx);


            Gate_V = ps_initial_voltage; % 게이트 초기전압 설정
            if kV_test == 1
                current_reached = true;
            else
                current_reached = false;
            end

            integral = 0; %PID 계수 초기화
            error_pid = 0; %PID 계수 초기화
            prev_error = 0; %PID 계수 초기화

            % fprintf(ps_obj, 'HVON');
            % fprintf(multi_obj, ':READ?');
            % measured_voltage_DC = str2double(fscanf(multi_obj));
            % 
            % Anode_mA_DC = round(measured_voltage_DC, 6);
            % Anode_mA_offset = Anode_mA_DC*100/duty;
            


            while ~current_reached % 목표 전류에 도달할때까지 동작
               
             
           
         
                loop_start_time = toc(start_time);

              
                [tripped, reason] = handle_fault();
                if tripped
                    abort_and_throw(reason);
                end


               % ardu_ping()



                %% 컨버테크: Gate 전압 설정 (현재 Gate_V 그대로 유지)
                ratio = round((Gate_V / maxVoltage) * 1000);
                SVH = bitor(floor(ratio / 64), 0x40);
                SVL = bitor(mod(ratio, 64), 0x40);
                frameB = [0x02 id 'B' SVH SVL 0x03];
                send_with_ack_retry(ps_obj, frameB, 'B', 0.3, 1);  % ACK 0.3초, 재시도 1회


                %% 컨버테크: 상태 읽기 → Gate 전류 측정
                flush(ps_obj, "input");
                write(ps_obj, [0x02 id 'A' 0x40 0x40 0x03], "uint8");
                try
                    data = read(ps_obj, 15, "uint8");
                catch ME
                    warning('RAMP: 컨버테크 A커맨드 read 타임아웃: %s', ME.message);
                    continue;
                end

                if data(1) ~= 0x02
                    warning('RAMP: A 프레임 동기화 깨짐. 첫 바이트=0x%02X', data(1));
                    continue;
                end


                MIH = double(bitand(data(4), 0x3F));
                MIL = double(bitand(data(5), 0x3F));
                Gate_mA = ((MIH*64) + MIL)*maxCurrent; 
                Gate_mA_norm = Gate_mA*100/duty;



                % === Gate 전류 보정 ===
                if isnan(R_dc)
                    Gate_mA_DC = 0;
                    Gate_mA_a = Gate_mA*100/duty;  % 게이트누설전류 뺸 전계방출 게이트 전류 (듀티고려)
                else
                    Gate_mA_DC = Gate_V / R_dc;
                    Gate_mA_a = max((Gate_mA - Gate_mA_DC) * 100/duty, 0);  % 게이트누설전류 뺸 전계방출 게이트 전류 (듀티고려)
                end


                % 2) 상태 읽기 (A 커맨드: blocking read 사용)
                flush(ps_obj_A, "input");
                write(ps_obj_A, [0x02 id_A 'A' 0x40 0x40 0x03], "uint8");
                try
                    data = read(ps_obj_A, 15, "uint8");
                catch ME
                    warning('RAMP: 컨버테크 A커맨드 read 타임아웃: %s', ME.message);
                    continue;
                end

                if data(1) ~= 0x02
                    warning('RAMP: A 프레임 동기화 깨짐. 첫 바이트=0x%02X', data(1));
                    continue;
                end


                % --- 측정 전압 (kV) ---
                MVH = double(bitand(data(2), 0x3F));
                MVL = double(bitand(data(3), 0x3F));
                ratioV_meas      = MVH*64 + MVL;                         % 0~1000
                V_meas_kV        = ratioV_meas * maxVoltage_kV_A / 1000; % [kV]
                current_kV_output = V_meas_kV;                           % 측정 애노드 전압

                % --- 측정 전류 (mA) ---
                MIH = double(bitand(data(4), 0x3F));
                MIL = double(bitand(data(5), 0x3F));
                ratioI_meas   = MIH*64 + MIL;                            % 0~1000
                ratioI_meas = max(0, min(1000, ratioI_meas));
                I_meas_A_A    = maxCurrent_A * ratioI_meas / 1000;       % [A]
                I_meas_mA_A   = I_meas_A_A * 1000;                       % [mA]
                % 여기서는 "지금 측정된 애노드 전류"를 Anode_mA_offset에 매핑
                Anode_mA = round(I_meas_mA_A*100/duty, 3);
                Anode_mA = Anode_mA - Anode_mA_offset ;
                Anode_mA = max(0, Anode_mA - Anode_mA_offset);

                % --- 설정 전압 (kV, 장비 내부값) ---
                SVH_r = double(bitand(data(6), 0x3F));
                SVL_r = double(bitand(data(7), 0x3F));
                ratioV_set     = SVH_r*64 + SVL_r;                       % 0~1000
                V_set_read_kV  = ratioV_set * maxVoltage_kV_A / 1000;    % [kV]

                % --- dV 계산 (설정 - 측정) ---
                dV_kV_ramp = V_set_read_kV - current_kV_output;          % [kV]

                % === ARC 체크 ===
                if abs(dV_kV_ramp) >= dv_threshold_kV_A
                    fprintf('\n!!! ARC DETECTED DURING RAMP: dV = %.2f kV → ARC 플래그 세팅 !!!\n', dV_kV_ramp);

                    % Spellman 타이머 대신: ARC 플래그만 올림
                    raise_arc_flag_from_convatech("RAMP", ...
                        dV_kV_ramp, ...
                        V_set_read_kV, ...
                        current_kV_output);

                    % 이 루프는 종료 → 다음 반복에서 handle_fault()가 캐치
                    break;
                end
                
                Trans = 0;
                Trans_real = 0;


                % % % 에노드전류 읽기 - 미세 누설전류 확인용이라 멀티미터로 읽음
                % fprintf(multi_obj, ':READ?');
                % measured_voltage = str2double(fscanf(multi_obj));
                % Anode_mA = round(measured_voltage*6.7*100/duty, 3); % 지금 전계방출 전이라 오프셋으로 저장
                % Anode_mA = Anode_mA - Anode_mA_offset;


                % % 데이터 기록
                all_times = [all_times, loop_start_time];
                all_currents = [all_currents, Anode_mA];
                all_voltages = [all_voltages, Gate_V];
                all_ps_currents = [all_ps_currents, Gate_mA_a];
                all_Trans = [all_Trans, 0];
                all_spellman_voltages = [all_spellman_voltages, spellman_voltage];
                all_gate_DC = [all_gate_DC, Gate_mA_DC];

                addpoints(h_current, loop_start_time, Anode_mA);
                addpoints(h_voltage, loop_start_time, Gate_V);
                addpoints(h_ps_current, loop_start_time, Gate_mA_a);
                addpoints(h_Anode_V, loop_start_time, spellman_voltage);
                addpoints(h_Trans, loop_start_time, Trans_real);
                addpoints(h_Gate_DC, loop_start_time, Gate_mA_DC);

               
                drawnow limitrate;
              

                fprintf('Cycle: %2d | Time: %.1f s | Anode V: %d kV| Target: %.1f mA | Gate_V: %.1f V | Anode: %.3f mA | Gate_norm: %.3f mA | Trans: %.2f%% | Gate_real: %.3f mA | Trans_real: %.2f%% \n', ...
                    cycle_idx, loop_start_time, spellman_voltage, target_current, Gate_V, Anode_mA, Gate_mA_norm, Trans ,Gate_mA_a, Trans_real);

                raw_data = [raw_data; {cycle_idx, loop_start_time, "Approach", spellman_voltage, target_current, Gate_V, Anode_mA, Gate_mA_norm, Trans, Gate_mA_a, Trans_real, R_dc []}];

                %PID 피드백
                error_pid = target_current - Anode_mA; % 에러값 계산 (비례계수P)
                % error_pid = target_current - (Anode_mA+ Gate_mA_norm); % 에러값 계산 (비례계수P)

                integral = integral + error_pid; % 누적항 계산 (적분계수I)
                integral = max(min(integral, 1000), -10); %누적항 한계치 설정 -1000~1000
                derivative = error_pid - prev_error;% 변화율 계산(미분계수D)
                pid_adjustment = max(min(Kp * error_pid + Ki * integral + Kd * derivative, ps_voltage_range), -ps_voltage_range); % 피드백 제어 한계치 설정


                % PID 에러값 저장 (확인용)
                error_log = [error_log; loop_start_time, error_pid, integral, derivative, pid_adjustment];
                pid_adjustment_log = [pid_adjustment_log; loop_start_time, pid_adjustment];


                if error_pid < 0
                    Gate_V = Gate_V - abs(pid_adjustment); % 에노드 전압이 목표전압보다 크면 게이트 전압 하강
                else
                    Gate_V = Gate_V + pid_adjustment; % 에노드 전압이 목표전압보다 작으면 게이트 전압 상승
                end

                Gate_V = max(0, min(Gate_V, ps_voltage_limit)); %게이트 전압 한계치 설정
                Gate_V = round(Gate_V);
                prev_error = error_pid; %직전 에러 저장

                if error_pid > -1 && error_pid <=1
                    integral = 0; % 적분 항 초기화
                end

                if error_pid > -1 && error_pid <=1
                % if error_pid > 0 && error_pid <=0.2
                    current_reached = true; % 에노드전류, 목표전류 차이가 n미만이면 도달했다고 판정
                    integral = 0; % 적분 항 초기화
                end

                % % ---- FAIL 2: 투과율 하한 ----
                % if ~isnan(Trans_real) && (Trans_real < fail_trans_threshold)
                %     abortAll = true; fail_reason = "LOW_TRANS";
                %     do_emergency_shutdown(writeCmd, ps_obj);
                %     break;
                % end

                % ---- FAIL 3: 게이트 전압 상한 ----
                if Gate_V > fail_gate_v_limit
                    abort_and_throw("GATE_OVER_V");
                end




                % 0.2초 간격으로 대기
                next_execution_time = step_interval - mod(toc(start_time), step_interval);
                pause(max(0, next_execution_time));
            end
 
            if restartCycle
                restartCycle = false; continue;
            end

            %% 목표 유지 루프
            if hold_time > 0 % 쉬는시간 설정이 되있으면 동작
                hold_start_time = tic; % 타이머 시작
                while toc(hold_start_time) < hold_time
                   
                

                    
        
                    loop_start_time = toc(start_time);

                    [tripped, reason] = handle_fault();
                    if tripped
                        abort_and_throw(reason);
                    end

                    
                    % ardu_ping()

                    %% 컨버테크: Gate 전압 설정 (현재 Gate_V 그대로 유지)
                    ratio = round((Gate_V / maxVoltage) * 1000);
                    SVH = bitor(floor(ratio / 64), 0x40);
                    SVL = bitor(mod(ratio, 64), 0x40);
                    frameB = [0x02 id 'B' SVH SVL 0x03];
                    send_with_ack_retry(ps_obj, frameB, 'B', 0.3, 1);  % ACK 0.3초, 재시도 1회


                    %% 컨버테크: 상태 읽기 → Gate 전류 측정
                    flush(ps_obj, "input");
                    write(ps_obj, [0x02 id 'A' 0x40 0x40 0x03], "uint8");
                    try
                        data = read(ps_obj, 15, "uint8");
                    catch ME
                        warning('RAMP: 컨버테크 A커맨드 read 타임아웃: %s', ME.message);
                        continue;
                    end

                    if data(1) ~= 0x02
                        warning('RAMP: A 프레임 동기화 깨짐. 첫 바이트=0x%02X', data(1));
                        continue;
                    end


                    MIH = double(bitand(data(4), 0x3F));
                    MIL = double(bitand(data(5), 0x3F));
                    Gate_mA = ((MIH*64) + MIL)*maxCurrent;
                    Gate_mA_norm = Gate_mA*100/duty;

                    % === Gate 전류 보정 ===
                    if isnan(R_dc)
                        Gate_mA_DC = 0;
                        Gate_mA_a = Gate_mA*100/duty;  % 보정 불가 → 전체 전류를 그대로 사용
                    else
                        Gate_mA_DC = Gate_V / R_dc;
                        Gate_mA_a = max((Gate_mA - Gate_mA_DC) * 100/duty, 0);  % 듀티 고려 보정
                    end


                    % 2) 상태 읽기 (A 커맨드: blocking read 사용)
                    flush(ps_obj_A, "input");
                    write(ps_obj_A, [0x02 id_A 'A' 0x40 0x40 0x03], "uint8");
                    try
                        data = read(ps_obj_A, 15, "uint8");
                    catch ME
                        warning('RAMP: 컨버테크 A커맨드 read 타임아웃: %s', ME.message);
                        continue;
                    end

                    if data(1) ~= 0x02
                        warning('RAMP: A 프레임 동기화 깨짐. 첫 바이트=0x%02X', data(1));
                        continue;
                    end


                    % --- 측정 전압 (kV) ---
                    MVH = double(bitand(data(2), 0x3F));
                    MVL = double(bitand(data(3), 0x3F));
                    ratioV_meas      = MVH*64 + MVL;                         % 0~1000
                    V_meas_kV        = ratioV_meas * maxVoltage_kV_A / 1000; % [kV]
                    current_kV_output = V_meas_kV;                           % 측정 애노드 전압

                    % --- 측정 전류 (mA) ---
                    MIH = double(bitand(data(4), 0x3F));
                    MIL = double(bitand(data(5), 0x3F));
                    ratioI_meas   = MIH*64 + MIL;                            % 0~1000
                    ratioI_meas = max(0, min(1000, ratioI_meas));
                    I_meas_A_A    = maxCurrent_A * ratioI_meas / 1000;       % [A]
                    I_meas_mA_A   = I_meas_A_A * 1000;                       % [mA]
                    % 여기서는 "지금 측정된 애노드 전류"를 Anode_mA_offset에 매핑
                    Anode_mA = round(I_meas_mA_A*100/duty, 3);
                    Anode_mA = Anode_mA - Anode_mA_offset ;
                    Anode_mA = max(0, Anode_mA - Anode_mA_offset);

                    % --- 설정 전압 (kV, 장비 내부값) ---
                    SVH_r = double(bitand(data(6), 0x3F));
                    SVL_r = double(bitand(data(7), 0x3F));
                    ratioV_set     = SVH_r*64 + SVL_r;                       % 0~1000
                    V_set_read_kV  = ratioV_set * maxVoltage_kV_A / 1000;    % [kV]

                    % --- dV 계산 (설정 - 측정) ---
                    dV_kV_ramp = V_set_read_kV - current_kV_output;          % [kV]

                    % === ARC 체크 ===
                    if abs(dV_kV_ramp) >= dv_threshold_kV_A
                        fprintf('\n!!! ARC DETECTED DURING RAMP: dV = %.2f kV → ARC 플래그 세팅 !!!\n', dV_kV_ramp);

                        % Spellman 타이머 대신: ARC 플래그만 올림
                        raise_arc_flag_from_convatech("RAMP", ...
                            dV_kV_ramp, ...
                            V_set_read_kV, ...
                            current_kV_output);

                        % 이 루프는 종료 → 다음 반복에서 handle_fault()가 캐치
                        break;
                    end

                    % % % 에노드전류 읽기 - 미세 누설전류 확인용이라 멀티미터로 읽음
                    % fprintf(multi_obj, ':READ?');
                    % measured_voltage = str2double(fscanf(multi_obj));
                    % Anode_mA = round(measured_voltage*6.7*100/duty, 3); % 지금 전계방출 전이라 오프셋으로 저장
                    % Anode_mA = Anode_mA - Anode_mA_offset;



                    % 투과율 계산
                    Trans_real = round((Anode_mA / (Anode_mA + Gate_mA_a)) * 100, 2);
                    Trans = round((Anode_mA / (Anode_mA + Gate_mA_norm)) * 100, 2);

                    % % 데이터 기록
                    all_times = [all_times, loop_start_time];
                    all_currents = [all_currents, Anode_mA];
                    all_voltages = [all_voltages, Gate_V];
                    all_ps_currents = [all_ps_currents, Gate_mA_a];
                    all_Trans = [all_Trans, 0];
                    all_spellman_voltages = [all_spellman_voltages, spellman_voltage];
                    all_gate_DC = [all_gate_DC, Gate_mA_DC];

                    addpoints(h_current, loop_start_time, Anode_mA);
                    addpoints(h_voltage, loop_start_time, Gate_V);
                    addpoints(h_ps_current, loop_start_time, Gate_mA_a);
                    addpoints(h_Anode_V, loop_start_time, spellman_voltage);
                    addpoints(h_Trans, loop_start_time, Trans_real);
                    addpoints(h_Gate_DC, loop_start_time, Gate_mA_DC);

                   

                    drawnow limitrate;


                    % 상태 출력
                    fprintf('Cycle(hold): %2d | Time: %.1f s | Anode V: %d kV| Target: %.1f mA | Gate_V: %.1f V | Anode: %.3f mA | Gate_norm: %.3f mA | Trans: %.2f%% | Gate_real: %.3f mA | Trans_real: %.2f%% \n', ...
                    cycle_idx, loop_start_time, spellman_voltage, target_current, Gate_V, Anode_mA, Gate_mA_norm, Trans ,Gate_mA_a, Trans_real);

                    % Raw Data 저장 (Hold 단계)
                    raw_data = [raw_data; {cycle_idx, loop_start_time, "Hold", spellman_voltage, target_current, Gate_V, Anode_mA, Gate_mA_norm, Trans, Gate_mA_a, Trans_real, R_dc [num2str(hold_time), 's']}];
                    
                    % PID 임계값 설정
                    error_threshold_hold = 1;

                    % PID 피드백 조건 적용
                    error_pid = target_current - Anode_mA;

                    % error_pid = target_current - (Anode_mA+ Gate_mA_norm); % 에러값 계산 (비례계수P)
                    if abs(error_pid) > error_threshold_hold
                        integral = integral + error_pid;
                        integral = max(min(integral, 1000), -1000);
                        derivative = error_pid - prev_error;
                        pid_adjustment = max(min(Kp * error_pid + Ki * integral + Kd * derivative, ps_voltage_range), -ps_voltage_range);

                        % 에러값 저장
                        error_log = [error_log; loop_start_time, error_pid, integral, derivative, pid_adjustment];
                        pid_adjustment_log = [pid_adjustment_log; loop_start_time, pid_adjustment];

                        if error_pid < 0.5
                            Gate_V = Gate_V - abs(pid_adjustment);
                        elseif error_pid > 0
                            Gate_V = Gate_V + pid_adjustment;
                        end

                        Gate_V = max(0, min(Gate_V, ps_voltage_limit));
                        Gate_V = round(Gate_V);
                    end
                    
                    % ---- FAIL 2: 투과율 하한 ----
                    % if ~isnan(Trans_real) && (Trans_real < fail_trans_threshold)
                    %     abortAll = true; fail_reason = "LOW_TRANS";
                    %     do_emergency_shutdown(writeCmd, ps_obj);
                    %     break;
                    % end

                    % ---- FAIL 3: 게이트 전압 상한 ----
                    if Gate_V > fail_gate_v_limit
                        abort_and_throw("GATE_OVER_V");
                    end




                    % 직전 에러 저장 (조건과 상관없이)
                    prev_error = error_pid;

                   
                    % 0.2초 간격으로 대기
                    next_execution_time = step_interval_hold - mod(toc(start_time), step_interval_hold);
                    pause(max(0, next_execution_time));

                end
              
                if restartCycle
                    restartCycle = false; continue;
                end

            end
           
         
            fprintf('Hold complete. Moving to next cycle.\n');

            % raw_data를 테이블로 변환 (기존 변수에서 테이블로 처리 시 필요)
            raw_data_table = cell2table(raw_data, 'VariableNames', ...
                {'Cycle', 'Time', 'Phase', 'Spellman_Voltage', 'Target_Anode_mA', ...
                'Gate_Voltage', 'Anode_Current', 'Gate_mA', 'Trans', 'Gate_mA_real', 'Trans_real', 'Gate_R', 'Additional_Info'});
            % 마지막 num_last_rows 행을 가져오기
            last_rows = raw_data_table(end-min(num_last_rows, height(raw_data_table))+1:end, :);

            % 숫자형 데이터만 평균 계산 (Phase, Additional_Info 제외)
            numeric_columns = varfun(@isnumeric, last_rows, 'OutputFormat', 'uniform'); % 숫자 열만 추출
            averaged_row = [averaged_row; varfun(@mean, last_rows(:, numeric_columns), 'OutputFormat', 'table')];


            %% 전류 유지 루프 후 동작 (장비 off 후 휴식 / 시간 포함됨)
            fprintf('Cycle %d | Entering Rest Period.\n', cycle_idx);

          

            %% 장비 초기화

            SVH = bitor(0, 0x40);
            SVL = bitor(0, 0x40);

            frameB = [0x02 id 'B' SVH SVL 0x03];
            send_with_ack_retry(ps_obj, frameB, 'B', 0.3, 1);  % ACK 0.3초, 재시도 1회

            frameB = [0x02 id_A 'B' SVH SVL 0x03];
            send_with_ack_retry(ps_obj_A, frameB, 'B', 0.3, 1);  % ACK 0.3초, 재시도 1회


      
            pause(0.05);
            % write(ps_obj, [0x02 id 'E' 0x40 0x40 0x03], "uint8"); % 출력 OFF
            % pause(0.05); % D가 ON E 가 전압 OFF

         


            % 쉬는 시간 동안 데이터 기록
            rest_start_time = tic;
            while toc(rest_start_time) < rest_time
                
              
                loop_start_time = toc(start_time);  % 스텝 시작 시간

                [tripped, reason] = handle_fault();
                if tripped
                    abort_and_throw(reason);
                end

                % ardu_ping()

                % % 데이터 기록
                all_times = [all_times, loop_start_time];
                all_currents = [all_currents, 0];
                all_voltages = [all_voltages, 0];
                all_ps_currents = [all_ps_currents, 0];
                all_Trans = [all_Trans, 0];
                all_spellman_voltages = [all_spellman_voltages, 0];
                all_gate_DC = [all_gate_DC, 0];


                addpoints(h_current, loop_start_time, 0);
                addpoints(h_voltage, loop_start_time, 0);
                addpoints(h_ps_current, loop_start_time, 0);
                addpoints(h_Anode_V, loop_start_time, 0);
                addpoints(h_Trans, loop_start_time, 0);
                addpoints(h_Gate_DC, loop_start_time, 0);

             
                drawnow limitrate;

                % 다음루프 들어갈 준비
                remaining_time = round(rest_time - toc(rest_start_time));
                if remaining_time <= 60
                    fprintf('>> [Notice] 휴식 종료까지 %d초 남았습니다.\n', remaining_time);
                end

                raw_data = [raw_data; {cycle_idx, loop_start_time, "Rest", 0, 0, 0, 0, 0, 0, 0, 0, 0, "Voltage Off"}];

                % 출력 메시지에 타임스탬프 추가
                fprintf('Cycle: %2d | Time: %.1f s | Rest Period Active | Target: %.1f mA | Voltage: 0 V | Current: 0 mA\n', ...
                    cycle_idx, loop_start_time, target_current);
                
                % 0.2초 간격으로 대기
                next_execution_time = step_interval_off - mod(toc(start_time), step_interval_off);
                pause(max(0, next_execution_time));
            end
           

            if restartCycle
                restartCycle = false; continue;
            end
            cycle_idx = cycle_idx + 1;
        end % 사이클 루프
        
    end % 전류 목표 루프
   
end % 스펠만 전압 루프 


%% 엑셀 저장

% ardu_ping()
% 현재 시간 추가
current_time = datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'); % 현재 시간을 형식 지정
file_name = sprintf('experiment_results_%s.xlsx', char(current_time)); % 시간 추가한 파일 이름 생성

% 전체 경로 생성
full_path = fullfile(save_path, file_name);

% 데이터 테이블 생성 및 저장
raw_data_table = cell2table(raw_data, 'VariableNames', ...
    {'Cycle', 'Time', 'Phase', 'Spellman_Voltage', 'Target_Anode_mA', ...
                'Gate_Voltage', 'Anode_Current', 'Gate_mA', 'Trans', 'Gate_mA_real', 'Trans_real', 'Gate_R', 'Additional_Info'});

% 엑셀 파일 저장
writetable(raw_data_table, full_path, 'Sheet', 1);
% ardu_ping()
% 평균 데이터 저장
if istable(averaged_row)
    writetable(averaged_row, full_path, 'Sheet', 2, 'WriteMode', 'append');
else
    % 아무것도 안 하거나, 필요하면 writematrix로 대체
    % writematrix(averaged_row, full_path, 'Sheet', 2, 'WriteMode', 'append');
end

% 메시지 출력
disp(['엑셀 파일이 저장되었습니다: ', full_path]);
disp('마지막 5개 평균 데이터가 엑셀 시트 2에 저장되었습니다.');

%% 플롯 저장 (메트랩 피규어 저장 추가)
% % 플롯 파일 이름 설정
% set(gcf, 'Units', 'normalized', 'OuterPosition', [0 0 1 1]);
figure_file_name = sprintf('experiment_plot_%s.png', char(current_time)); % 시간 추가한 파일 이름 생성
figure_full_path = fullfile(save_path, figure_file_name); % 전체 경로 생성
% saveas(gcf, figure_full_path,'jpg'); %
exportgraphics(gcf, figure_full_path, 'Resolution', 300);
% 메시지 출력
disp(['플롯 이미지가 저장되었습니다: ', figure_full_path]);
% ardu_ping()

setappdata(0,'NORMAL_COMPLETION', true);


%% 장비 종료


% 전압 0 설정 (B COMMAND)
ratio = 0; % 0V로 설정
SVH = bitor(floor(ratio / 64), 0x40);
SVL = bitor(mod(ratio, 64), 0x40);
write(ps_obj_A, [0x02 id 'B' SVH SVL 0x03], "uint8");
write(ps_obj, [0x02 id 'B' SVH SVL 0x03], "uint8");

pause(0.1); % B 가 전압 설정
% write(ardu, CMD_PING, "uint8");

% 출력 OFF
write(ps_obj_A, [0x02 id 'E' 0x40 0x40 0x03], "uint8"); % 출력 OFF
write(ps_obj, [0x02 id 'E' 0x40 0x40 0x03], "uint8"); % 출력 OFF
pause(0.1); % D가 ON E 가 전압 OFF
% write(ardu, CMD_PING, "uint8");

disp('컨버테크 파워서플라이 종료');


% 
% fclose(multi_obj);
% delete(multi_obj);

% ★★★ serialport 반드시 해제 (다음 실험을 위해 필수) ★★★
try, delete(ps_obj_A); catch, end
try, delete(ps_obj);   catch, end
ps_obj_A = [];
ps_obj   = [];

pause(0.5);  % ★ 포트 해제 OS 반영 시간(중요)

% ★ 혹시 남아있는 COM20/COM21 핸들이 있으면 강제 제거
try
    old20 = serialportfind("Port","COM20"); if ~isempty(old20), delete(old20); end
catch, end
try
    old21 = serialportfind("Port","COM21"); if ~isempty(old21), delete(old21); end
catch, end

pause(0.2);



% 
% fclose(fun_obj);
delete(fun_obj);

end
