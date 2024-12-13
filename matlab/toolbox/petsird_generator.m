function petsird_generator(output)

arguments
    output (1,1) string
end

% These are constants for now
config.NUMBER_OF_ENERGY_BINS = 3;
config.NUMBER_OF_TOF_BINS = 300;
config.RADIUS = 400;
config.CRYSTAL_LENGTH = [20, 4, 4];
config.NUM_CRYSTALS_PER_MODULE = [2, 4, 7];
config.NUM_MODULES_ALONG_RING = 20;
config.NUM_MODULES_ALONG_AXIS = 2;
config.MODULE_AXIS_SPACING = (config.NUM_CRYSTALS_PER_MODULE(3) + 4) * config.CRYSTAL_LENGTH(3);
config.NUMBER_OF_TIME_BLOCKS = 6;
config.COUNT_RATE = 500;

writer = petsird.binary.PETSIRDWriter(output);

header = get_header(config);
writer.write_header(header);

for t = 0:config.NUMBER_OF_TIME_BLOCKS-1
    start = t * header.scanner.event_time_block_duration;
    % NOTE: Need Statistics and Machine Learning Toolbox for Poisson distribution functions
    % num_prompts_this_block = poissrnd(COUNT_RATE);
    num_prompts_this_block = randi(config.COUNT_RATE);
    prompts_this_block = get_events(header, num_prompts_this_block, config);

    tb = petsird.TimeBlock.EventTimeBlock(...
        petsird.EventTimeBlock(start=start, prompt_events=prompts_this_block) ...
    );
    writer.write_time_blocks(tb)
end

writer.end_time_blocks();
writer.close();

end

function h = get_header(cfg)
    subject = petsird.Subject(id="123456");
    institution = petsird.Institution(name="University of Somewhere", address="Didcot, Oxfordshire, Ox11 0DE, UK");
    h = petsird.Header();
    h.exam = petsird.ExamInformation(subject=subject, institution=institution);
    h.scanner = get_scanner_info(cfg);
end

function scanner = get_scanner_info(cfg)
    scanner_geometry = get_scanner_geometry(cfg);

    % TOF info (in mm)
    tofBinEdges = single(linspace(-cfg.RADIUS, cfg.RADIUS, cfg.NUMBER_OF_TOF_BINS + 1));
    energyBinEdges = single(linspace(430, 650, cfg.NUMBER_OF_ENERGY_BINS + 1));

    % We need energy bin info before being able to construct the detection
    % efficiencies, so we first construct a scanner without the efficiencies
    scanner = petsird.ScannerInformation(...
        model_name="PETSIRD_TEST", ...
        scanner_geometry=scanner_geometry, ...
        tof_bin_edges=tofBinEdges, ...
        tof_resolution=9.4, ... % in mm
        energy_bin_edges=energyBinEdges, ...
        energy_resolution_at_511=0.11, ... % as fraction of 511
        event_time_block_duration=1 ... % ms
    );

    % Now added the efficiencies
    scanner.detection_efficiencies = get_detection_efficiencies(scanner, cfg);
end

function geometry = get_scanner_geometry(cfg)
    detector_module = get_detector_module(cfg);

    rep_module = petsird.ReplicatedDetectorModule(object=detector_module);
    module_id = 0;
    for i = 0:cfg.NUM_MODULES_ALONG_RING-1
        angle = 2 * pi * i / cfg.NUM_MODULES_ALONG_RING;
        for ax_mod = 0:cfg.NUM_MODULES_ALONG_AXIS-1
            transform = petsird.RigidTransformation(matrix=...
                transpose([...
                    cos(angle), -sin(angle), 0, 0; ...
                    sin(angle), cos(angle), 0, 0; ...
                    0, 0, 1, cfg.MODULE_AXIS_SPACING * ax_mod; ...
                ]) ...
            );
            rep_module.transforms = [rep_module.transforms transform];
            rep_module.ids = [rep_module.ids module_id];
            module_id = module_id + 1;
        end
    end

    geometry = petsird.ScannerGeometry(replicated_modules=[rep_module], ids=[0]);
end

function detector = get_detector_module(cfg)
    % Return a module of NUM_CRYSTALS_PER_MODULE cuboids
    crystal = get_crystal(cfg);
    rep_volume = petsird.ReplicatedBoxSolidVolume(object=crystal);
    N0 = cfg.NUM_CRYSTALS_PER_MODULE(1);
    N1 = cfg.NUM_CRYSTALS_PER_MODULE(2);
    N2 = cfg.NUM_CRYSTALS_PER_MODULE(3);
    id = 0;
    for rep0 = 0:N0-1
        for rep1 = 0:N1-1
            for rep2 = 0:N2-1
                transform = petsird.RigidTransformation(matrix=...
                    transpose([...
                        1, 0, 0, cfg.RADIUS + rep0 * cfg.CRYSTAL_LENGTH(1); ...
                        0, 1, 0, (rep1 - N1 / 2) * cfg.CRYSTAL_LENGTH(2); ...
                        0, 0, 1, (rep2 - N2 / 2) * cfg.CRYSTAL_LENGTH(3); ...
                    ]));
                rep_volume.transforms = [rep_volume.transforms transform];
                rep_volume.ids = [rep_volume.ids id];
                id = id + 1;
            end
        end
    end
    detector = petsird.DetectorModule(detecting_elements=[rep_volume], detecting_element_ids=[0]);
end

function crystal = get_crystal(cfg)
    % Return a cuboid shape
    crystal_shape = petsird.BoxShape(...
        corners = [...
            petsird.Coordinate(c=[0, 0, 0]), ...
            petsird.Coordinate(c=[0, 0, cfg.CRYSTAL_LENGTH(3)]), ...
            petsird.Coordinate(c=[0, cfg.CRYSTAL_LENGTH(2), cfg.CRYSTAL_LENGTH(3)]), ...
            petsird.Coordinate(c=[0, cfg.CRYSTAL_LENGTH(2), 0]), ...
            petsird.Coordinate(c=[cfg.CRYSTAL_LENGTH(1), 0, 0]), ...
            petsird.Coordinate(c=[cfg.CRYSTAL_LENGTH(1), 0, cfg.CRYSTAL_LENGTH(3)]), ...
            petsird.Coordinate(c=[cfg.CRYSTAL_LENGTH(1), cfg.CRYSTAL_LENGTH(2), cfg.CRYSTAL_LENGTH(3)]) ...
            petsird.Coordinate(c=[cfg.CRYSTAL_LENGTH(1), cfg.CRYSTAL_LENGTH(2), 0]), ...
        ]);
    crystal = petsird.BoxSolidVolume(shape=crystal_shape, material_id=1);
end

function efficiencies = get_detection_efficiencies(scanner, cfg)
    % Return some (non-physical) detection efficiencies
    num_det_els = petsird.helpers.get_num_detecting_elements(scanner.scanner_geometry);

    % det_el_efficiencies = ones(num_det_els, scanner.number_of_energy_bins(), "single");
    det_el_efficiencies = ones(scanner.number_of_energy_bins(), num_det_els, "single");

    % Only 1 type of module in the current scanner
    assert(length(scanner.scanner_geometry.replicated_modules) == 1);
    rep_module = scanner.scanner_geometry.replicated_modules(1);
    num_modules = int32(length(rep_module.transforms));

    % We will use rotational symmetries translation along the axis
    % We assume all module-pairs are in coincidence, except those
    % with the same angle.
    % Writing a module number as (z-position, angle):
    %   eff((z1,a1), (z2, a2)) == eff((z1,0), (z2, abs(a2-a1)))
    % or in linear indices
    %   eff(z1 + NZ * a1, z2 + NZ * a2) == eff(z1, z2 + NZ * abs(a2 - a1))
    % (coincident) SGIDs need to start from 0, so ignoring self-coincident
    % angles we get
    %   SGID = z1 + NZ * (z2 + NZ * abs(a2 - a1) - 1)
    num_SGIDs = cfg.NUM_MODULES_ALONG_AXIS * cfg.NUM_MODULES_ALONG_AXIS * (cfg.NUM_MODULES_ALONG_RING - 1);
    NZ = cfg.NUM_MODULES_ALONG_AXIS;
    module_pair_SGID_LUT = zeros(num_modules, "int32");
    for mod1 = 0:num_modules-1
        for mod2 = 0:num_modules-1
            z1 = mod(mod1, NZ);
            a1 = idivide(mod1, NZ);
            z2 = mod(mod2, NZ);
            a2 = idivide(mod2, NZ);
            if a1 == a2
                module_pair_SGID_LUT(mod2+1, mod1+1) = -1;
            else
                module_pair_SGID_LUT(mod2+1, mod1+1) = z1 + NZ * (z2 + NZ * (abs(a2 - a1) - 1));
            end
        end
    end

    % fprint("SGID LUT:\n", module_pair_SGID_LUT, file=sys.stderr)
    assert(max(module_pair_SGID_LUT(:)) == num_SGIDs - 1);
    module_pair_efficiencies_vector = [];
    assert(length(rep_module.object.detecting_elements) == 1);
    detecting_elements = rep_module.object.detecting_elements(1);
    num_det_els_in_module = length(detecting_elements.transforms);
    for SGID = 0:num_SGIDs-1
        % Extract first module_pair for this SGID. However, as this
        % currently unused, it is commented out
        % module_pair = numpy.argwhere(module_pair_SGID_LUT == SGID)[0]
        % print(module_pair, file=sys.stderr)
        module_pair_efficiencies = ones(...
                scanner.number_of_energy_bins(), ...
                num_det_els_in_module, ...
                scanner.number_of_energy_bins(), ...
                num_det_els_in_module ...
        );
        % give some (non-physical) value
        module_pair_efficiencies = module_pair_efficiencies * SGID;
        module_pair_efficiencies_vector = [module_pair_efficiencies_vector ...
            petsird.ModulePairEfficiencies(values=module_pair_efficiencies, sgid=SGID)];
        assert(length(module_pair_efficiencies_vector) == SGID + 1);
    end

    efficiencies = petsird.DetectionEfficiencies(...
        det_el_efficiencies=det_el_efficiencies, ...
        module_pair_sgidlut=module_pair_SGID_LUT, ...
        module_pair_efficiencies_vector=module_pair_efficiencies_vector ...
    );
end


function events = get_events(header, num_events, cfg)
    % Generate some random events
    detector_count = petsird.helpers.get_num_detecting_elements(header.scanner.scanner_geometry);
    events = [];
    for i = 1:num_events
        while true
            detector_ids = int32([randi([0, detector_count-1]), randi([0, detector_count-1])]);
            mod_and_els = petsird.helpers.get_module_and_element(header.scanner.scanner_geometry, detector_ids);
            if header.scanner.detection_efficiencies.module_pair_sgidlut(mod_and_els(1).module+1, mod_and_els(2).module+1) >= 0
                % in coincidence, we can get out of the loop
                break
            end
        end

        events = [events, petsird.CoincidenceEvent(...
            detector_ids = detector_ids, ...
            energy_indices = [randi([0, cfg.NUMBER_OF_ENERGY_BINS-1]), randi([0, cfg.NUMBER_OF_ENERGY_BINS-1])], ...
            tof_idx=randi([0, cfg.NUMBER_OF_TOF_BINS-1])...
        )];
    end
end