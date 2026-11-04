use std::{env, fs};
use naga::{back::msl, valid::{Capabilities, ValidationFlags, Validator}};
fn main() {
    let args: Vec<_> = env::args().collect();
    let source = fs::read_to_string(&args[1]).unwrap();
    let module = naga::front::wgsl::parse_str(&source).unwrap_or_else(|e| panic!("{}", e.emit_to_string(&source)));
    let info = Validator::new(ValidationFlags::all(), Capabilities::all()).validate(&module)
        .unwrap_or_else(|e| panic!("{}", e.emit_to_string(&source)));
    let mut options = msl::Options::default();
    options.bounds_check_policies.index = naga::proc::BoundsCheckPolicy::Unchecked;
    options.bounds_check_policies.buffer = naga::proc::BoundsCheckPolicy::Unchecked;
    options.bounds_check_policies.image_load = naga::proc::BoundsCheckPolicy::Unchecked;
    options.lang_version = (2, 3);
    options.fake_missing_bindings = false;
    options.zero_initialize_workgroup_memory = false;
    options.force_loop_bounding = false;
    options.emit_int_div_checks = false;
    for ep in &module.entry_points {
        let mut resources = msl::EntryPointResources::default();
        resources.sizes_buffer = Some(30);
        for (_, var) in module.global_variables.iter() {
            if let Some(binding) = var.binding {
                let slot = binding.binding as u8;
                let mut target = msl::BindTarget::default();
                match module.types[var.ty].inner {
                    naga::TypeInner::Image { .. } => target.texture = Some(slot),
                    naga::TypeInner::Sampler { .. } => target.sampler = Some(msl::BindSamplerTarget::Resource(slot)),
                    _ => target.buffer = Some(slot),
                }
                resources.resources.insert(binding, target);
            }
        }
        options.per_entry_point_map.insert(ep.name.clone(), resources);
    }
    let (code, translation) = msl::write_string(&module, &info, &options, &msl::PipelineOptions::default()).unwrap();
    for entry in translation.entry_point_names { println!("{}", entry.unwrap()); }
    fs::write(&args[2], format!("// Native Metal shaders migrated from the original ocean equations using Naga.\n// Edit this file for native rendering; no WGSL or JavaScript runs in the app.\n{code}")).unwrap();
}
