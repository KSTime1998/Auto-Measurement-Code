function do_emergency_shutdown(ps_obj_A, ps_obj)

    id = bitor(uint8(0x40), uint8(0));
    SVH = bitor(0, 0x40);
    SVL = bitor(0, 0x40);

    % --- Anode 0V ---
    try
        if ~isempty(ps_obj_A)
            write(ps_obj_A, [0x02 id 'B' SVH SVL 0x03], "uint8");
        end
    catch
    end

    % --- Gate 0V ---
    try
        if ~isempty(ps_obj)
            write(ps_obj, [0x02 id 'B' SVH SVL 0x03], "uint8");
        end
    catch
    end

    pause(0.05);

    % --- Gate OFF ---
    try
        if ~isempty(ps_obj)
            write(ps_obj, [0x02 id 'E' 0x40 0x40 0x03], "uint8");
        end
    catch
    end

    % --- Anode OFF ---
    try
        if ~isempty(ps_obj_A)
            write(ps_obj_A, [0x02 id 'E' 0x40 0x40 0x03], "uint8");
        end
    catch
    end

    pause(0.05);
end
