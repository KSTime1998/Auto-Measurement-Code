function send_with_ack_retry(ps_obj, frame, cmdChar, ackTimeout, maxRetries)
% frame: write할 uint8 배열 (STX~ETX 포함)
% cmdChar: 'B','A' 등 (로그용)
% ackTimeout: ACK 기다리는 최대 시간
% maxRetries: 재시도 횟수 (예: 1이면 총 2번 시도)

    if nargin < 4 || isempty(ackTimeout), ackTimeout = 0.3; end
    if nargin < 5 || isempty(maxRetries), maxRetries = 1; end

    lastErr = [];
    for attempt = 1:(maxRetries+1)
        try
            flush(ps_obj, "input");                % 찌꺼기 제거(중요)
            write(ps_obj, frame, "uint8");         % 송신
            wait_ack(ps_obj, cmdChar, ackTimeout); % 여기서 timeout/invalid면 error
            return;                                % 성공하면 즉시 종료
        catch ME
            lastErr = ME;
            if attempt <= maxRetries
                warning('%s send failed (attempt %d/%d): %s', ...
                    cmdChar, attempt, maxRetries+1, ME.message);
                pause(0.05); % 짧은 딜레이 후 재시도
            end
        end
    end

    % 여기까지 오면 재시도까지 다 실패
    rethrow(lastErr);
end
