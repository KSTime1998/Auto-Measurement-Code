function tArc = start_arc_timer_shared(s, writeCmd, varargin)
% =========================================================================
% start_arc_timer_shared (Slim ver.)
%
% Spellman HV 상태 폴링 타이머 (감지 전용)
%   - CMD 22 (Request Status/Faults) 주기 송신
%   - ARC (ARG3), HV Ray On (ARG2) 파싱
%   - 감지 시 플래그만 세팅:
%       ARC_DETECTED = true  (rising edge)
%       INTERLOCK_FAULT = true (HV Ray 기대값과 다르면)
%
% [추가 기능]
%   - 타이머 내부 통신/코드 에러 발생 시
%     appdata에 COMM_ERROR_PENDING, COMM_ERROR_MSG 세팅
%     → main이 감지해서 error()로 처리 가능
% =========================================================================

% -------- 기본 플래그 준비 --------
if ~isappdata(0,'RUN_T0'),               setappdata(0,'RUN_T0', tic);          end
if ~isappdata(0,'SERIAL_BUSY'),          setappdata(0,'SERIAL_BUSY', false);   end

% ARC 관련
if ~isappdata(0,'ARC_DETECTED'),         setappdata(0,'ARC_DETECTED', false);  end
if ~isappdata(0,'ARC_DETECT_COUNT'),     setappdata(0,'ARC_DETECT_COUNT', uint32(0)); end
if ~isappdata(0,'ARC_LAST_FRAME'),       setappdata(0,'ARC_LAST_FRAME', "");   end

% INTERLOCK(HV Ray) 관련
if ~isappdata(0,'INTERLOCK_EXPECT'),     setappdata(0,'INTERLOCK_EXPECT', 1);  end % 보통 1(ON 기대)
if ~isappdata(0,'INTERLOCK_FAULT'),      setappdata(0,'INTERLOCK_FAULT', false); end
if ~isappdata(0,'INTERLOCK_LAST_FRAME'), setappdata(0,'INTERLOCK_LAST_FRAME', ""); end
if ~isappdata(0,'INTERLOCK_FAULT_TIME'), setappdata(0,'INTERLOCK_FAULT_TIME', 0); end

% ===== main으로 통신에러 올릴 플래그(추가) =====
if ~isappdata(0,'COMM_ERROR_PENDING'),   setappdata(0,'COMM_ERROR_PENDING', false); end
if ~isappdata(0,'COMM_ERROR_MSG'),       setappdata(0,'COMM_ERROR_MSG', ""); end
if ~isappdata(0,'COMM_ERROR_TIME'),      setappdata(0,'COMM_ERROR_TIME', 0); end
if ~isappdata(0,'COMM_ERROR_STACK'),     setappdata(0,'COMM_ERROR_STACK', []); end

% -------- 인자 파서 --------
p = inputParser;
addParameter(p,'PollPeriod',0.1,@(x)isnumeric(x)&&x>0);
addParameter(p,'RespWait',0.02,@(x)isnumeric(x)&&x>=0);
addParameter(p,'StartTime',[],@(x) isempty(x) || (isnumeric(x) && isscalar(x)));
parse(p, varargin{:});
cfg = p.Results;

STX = char(2); ETX = char(3);

    function arc_tick()
        % ===== TimerFcn 전체 보호 + 에러 main으로 전달 =====
        try
            persistent rxBuf_p lastArc_p t0local_p
            if isempty(rxBuf_p),  rxBuf_p  = uint8([]); end
            if isempty(lastArc_p), lastArc_p = 0;       end
            if isempty(t0local_p), t0local_p = tic;     end

            

            % 이미 ARC 감지된 상태면 불필요한 폴링 최소화
            if getappdata(0,'ARC_DETECTED'), return; end
            % 직렬 점유 중이면 스킵
            if getappdata(0,'SERIAL_BUSY'), return; end

            % 직전 TX 후 30ms 이내면 스킵
            RUN_T0 = getappdata(0,'RUN_T0');
            if isempty(RUN_T0), RUN_T0 = t0local_p; end
            lastTx = getappdata(0,'LAST_TX_T');
            nowT   = toc(RUN_T0);
            if ~isempty(lastTx) && (nowT - lastTx) < 0.03, return; end

            % 송신 (CMD 22)
            try
                writeCmd(22, "");
                
            catch MEw
                % === 통신(TX) 에러 -> main으로 던지기 ===
                setappdata(0,'COMM_ERROR_PENDING', true);
                setappdata(0,'COMM_ERROR_MSG', "Spellman writeCmd(22) TX fail: " + string(MEw.message));
                setappdata(0,'COMM_ERROR_TIME', toc(getappdata(0,'RUN_T0')));
                setappdata(0,'COMM_ERROR_STACK', MEw.stack);
                return;
            end

            % 응답 수신
            pause(cfg.RespWait);
            try
                nAvail = s.NumBytesAvailable;
                if nAvail > 0
                    bytes = read(s, nAvail, "uint8");
                    rxBuf_p = [rxBuf_p, bytes]; %#ok<AGROW>
                end
            catch MEr
                % === 통신(RX) 에러 -> main으로 던지기 ===
                setappdata(0,'COMM_ERROR_PENDING', true);
                setappdata(0,'COMM_ERROR_MSG', "Spellman RX read fail: " + string(MEr.message));
                setappdata(0,'COMM_ERROR_TIME', toc(getappdata(0,'RUN_T0')));
                setappdata(0,'COMM_ERROR_STACK', MEr.stack);
                return;
            end

            % 파싱
            arc = NaN; hvRay = NaN; frameStr = "";
            if ~isempty(rxBuf_p)
                txt = char(rxBuf_p);
                i1 = strfind(txt, STX);
                i2 = strfind(txt, ETX);
                if ~isempty(i1) && ~isempty(i2)
                    iStart = i1(end);
                    iEndC  = i2(i2 > iStart);
                    if ~isempty(iEndC)
                        iEnd   = iEndC(end);
                        frame  = txt(iStart+1:iEnd-1);
                        frameStr = string(frame);

                        if iEnd < length(txt)
                            rxBuf_p = uint8(txt(iEnd+1:end));
                        else
                            rxBuf_p = uint8([]);
                        end

                        % ===== parts를 무조건 string으로 고정 (에러 방지) =====
                        parts = string(split(frame, ','));

                        % 22,<ok>,...,ARG2,ARG3,... (길이 체크)
                        if ~isempty(parts) && parts(1)=="22" && ...
                           ~(numel(parts)>=2 && parts(2)=="!") && ...
                           numel(parts) >= (1+17)

                            vArc = str2double(parts(1+3)); % ARG3 = ARC
                            vHV  = str2double(parts(1+2)); % ARG2 = HV Ray On
                            if ~isnan(vArc), arc = vArc; end
                            if ~isnan(vHV),  hvRay = vHV; end
                        end
                    end
                end
            end

            % ARC rising edge 감지 → 플래그 세팅만
            if ~isnan(arc) && arc==1 && lastArc_p==0
                tNow = toc(getappdata(0,'RUN_T0'));
                newCnt = getappdata(0,'ARC_DETECT_COUNT') + 1;
                setappdata(0,'ARC_DETECT_COUNT', uint32(newCnt));
                setappdata(0,'ARC_DETECTED', true);
                setappdata(0,'ARC_LAST_FRAME', frameStr);
                fprintf('>>> ARC DETECTED #%d at %.3f s <<<\n', newCnt, tNow);
            end
            if ~isnan(arc), lastArc_p = arc; end

            % HV Ray 상태 감시 → 기대와 다르면 인터락 Fault
            if ~isnan(hvRay)
                expect = getappdata(0,'INTERLOCK_EXPECT');  % 보통 1
                if hvRay ~= expect && ~getappdata(0,'INTERLOCK_FAULT')
                    tNow = toc(getappdata(0,'RUN_T0'));
                    setappdata(0,'INTERLOCK_FAULT', true);
                    setappdata(0,'INTERLOCK_LAST_FRAME', frameStr);
                    setappdata(0,'INTERLOCK_FAULT_TIME', tNow);
                    fprintf('>>> HV RAY OFF Fault (ARG2=%d, expect=%d) at %.3f s <<<\n', hvRay, expect, tNow);
                end
            end

        catch ME
            % === 타이머 내부 코드 에러(파싱/비교 포함) -> main으로 던지기 ===
            setappdata(0,'COMM_ERROR_PENDING', true);
            setappdata(0,'COMM_ERROR_MSG', "ARC_Timer arc_tick ERROR: " + string(ME.message));
            setappdata(0,'COMM_ERROR_TIME', toc(getappdata(0,'RUN_T0')));
            setappdata(0,'COMM_ERROR_STACK', ME.stack);

            fprintf(">>> ARC_Timer arc_tick ERROR -> sent to main: %s\n", ME.message);
        end
    end

% -------- 타이머 생성 및 시작 --------
tArc = timer('ExecutionMode','fixedRate', ...
             'BusyMode','drop', ...
             'Period', cfg.PollPeriod, ...
             'TimerFcn', @(~,~) arc_tick(), ...
             'Name', 'ARC_Timer_Shared');
start(tArc);
end
