%% ===== 로컬 함수들 =====
function localWriteWithChecksum(sp, cmd, argstr)
    % payload(체크섬 대상) 만들기: "CC,ARG," 또는 인자가 없으면 "CC,"
    if nargin < 3 || isempty(argstr)
        payload = sprintf('%02d,', cmd);
    else
        % 주의: RS-232는 콤마가 인자 뒤에도 들어감
        payload = sprintf('%02d,%s,', cmd, argstr);
    end
    
    % 체크섬 계산 (매뉴얼 6.3 규칙)
    % 1) CMD~마지막 콤마까지 모든 바이트(ASCII)를 합산 (16비트 이상)
    bytes = uint8(payload);
    X = sum(uint16(bytes));                     % unsigned sum
    % 2) 2의 보수(negate) -> 3) 하위 8비트만 취함
    cs = uint16(256) - mod(X, 256);
    cs8 = uint8(bitand(cs, 127));               % 4) MSB 클리어 (& 0x7F)
    cs8 = bitor(cs8, uint8(64));                % 5) 다음 MSB 세팅 (| 0x40), 결과 0x40~0x7F
    
    % 최종 프레임: <STX>(0x02) + payload + <CSUM> + <ETX>(0x03)
    frame = [uint8(2), bytes, cs8, uint8(3)];
    write(sp, frame, "uint8");
end