// nnet3/nnet-nnet.cc

// Copyright      2015  Johns Hopkins University (author: Daniel Povey)
//                2016  Daniel Galvez
// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#include <iterator>
#include <sstream>
#include "nnet3/nnet-nnet.h"
#include "nnet3/nnet-parse.h"
#include "nnet3/nnet-utils.h"
#include "nnet3/nnet-simple-component.h"

namespace kaldi {
namespace nnet3 {

// returns dimension that this node outputs.
int32 NetworkNode::Dim(const Nnet &nnet) const {
  int32 ans;
  switch (node_type) {
    case kInput: case kDimRange:
      ans = dim;
      break;
    case kDescriptor:
      ans = descriptor.Dim(nnet);
      break;
    case kComponent:
      ans = nnet.GetComponent(u.component_index)->OutputDim();
      break;
    default:
      ans = 0;  // suppress compiler warning
      KALDI_ERR << "Invalid node type.";
  }
  KALDI_ASSERT(ans > 0);
  return ans;
}

const std::vector<std::string> &Nnet::GetNodeNames() const {
  return node_names_;
}

const std::vector<std::string> &Nnet::GetComponentNames() const {
  return component_names_;
}

std::string Nnet::GetAsConfigLine(int32 node_index, bool include_dim) const {
  std::ostringstream ans;
  KALDI_ASSERT(node_index < nodes_.size() &&
               nodes_.size() == node_names_.size());
  const NetworkNode &node = nodes_[node_index];
  const std::string &name = node_names_[node_index];
  switch (node.node_type) {
    case kInput:
      ans << "input-node name=" << name << " dim=" << node.dim;
      break;
    case kDescriptor:
      // assert that it's an output-descriptor, not one describing the input to
      // a component-node.
      KALDI_ASSERT(IsOutputNode(node_index));
      ans << "output-node name=" << name << " input=";
      node.descriptor.WriteConfig(ans, node_names_);
      if (include_dim)
        ans << " dim=" << node.Dim(*this);
      ans << " objective=" << (node.u.objective_type == kLinear ? "linear" :
                               "quadratic");
      break;
    case kComponent:
      ans << "component-node name=" << name << " component="
          << component_names_[node.u.component_index] << " input=";
      KALDI_ASSERT(nodes_[node_index-1].node_type == kDescriptor);
      nodes_[node_index-1].descriptor.WriteConfig(ans, node_names_);
      if (include_dim)
        ans << " input-dim=" << nodes_[node_index-1].Dim(*this)
            << " output-dim=" << node.Dim(*this);
      break;
    case kDimRange:
      ans << "dim-range-node name=" << name << " input-node="
          << node_names_[node.u.node_index] << " dim-offset="
          << node.dim_offset << " dim=" << node.dim;
      break;
    default:
      KALDI_ERR << "Unknown node type.";
  }
  return ans.str();
}

bool Nnet::IsOutputNode(int32 node) const {
  int32 size = nodes_.size();
  KALDI_ASSERT(node >= 0 && node < size);
  return (nodes_[node].node_type == kDescriptor &&
          (node + 1 == size ||
           nodes_[node + 1].node_type != kComponent));
}

bool Nnet::IsInputNode(int32 node) const {
  int32 size = nodes_.size();
  KALDI_ASSERT(node >= 0 && node < size);
  return (nodes_[node].node_type == kInput);
}

bool Nnet::IsDescriptorNode(int32 node) const {
  int32 size = nodes_.size();
  KALDI_ASSERT(node >= 0 && node < size);
  return (nodes_[node].node_type == kDescriptor);
}

bool Nnet::IsComponentNode(int32 node) const {
  int32 size = nodes_.size();
  KALDI_ASSERT(node >= 0 && node < size);
  return (nodes_[node].node_type == kComponent);
}

bool Nnet::IsDimRangeNode(int32 node) const {
  int32 size = nodes_.size();
  KALDI_ASSERT(node >= 0 && node < size);
  return (nodes_[node].node_type == kDimRange);
}


const Component *Nnet::GetComponent(int32 c) const {
  KALDI_ASSERT(static_cast<size_t>(c) < components_.size());
  return components_[c];
}

Component *Nnet::GetComponent(int32 c) {
  KALDI_ASSERT(static_cast<size_t>(c) < components_.size());
  return components_[c];
}

void Nnet::SetComponent(int32 c, Component *component) {
  KALDI_ASSERT(static_cast<size_t>(c) < components_.size());
  delete components_[c];
  components_[c] = component;
}

/// Returns true if this is component-input node, i.e. a node of type kDescriptor
/// that immediately precedes a node of type kComponent.
bool Nnet::IsComponentInputNode(int32 node) const {
  int32 size = nodes_.size();
  KALDI_ASSERT(node >= 0 && node < size);
  return (node + 1 < size &&
          nodes_[node].node_type == kDescriptor &&
          nodes_[node+1].node_type == kComponent);
}

void Nnet::GetConfigLines(bool include_dim,
                          std::vector<std::string> *config_lines) const {
  config_lines->clear();
  for (int32 n = 0; n < NumNodes(); n++)
    if (!IsComponentInputNode(n))
      config_lines->push_back(GetAsConfigLine(n, include_dim));

}

void Nnet::ReadConfig(std::istream &config_is) {

  std::vector<std::string> lines;
  // Write into "lines" a config file corresponding to whatever
  // nodes we currently have.  Because the numbering of nodes may
  // change, it's most convenient to convert to the text representation
  // and combine the existing and new config lines in that representation.
  const bool include_dim = false;
  GetConfigLines(include_dim, &lines);

  // we'll later regenerate what we need from nodes_ and node_name_ from the
  // string representation.
  nodes_.clear();
  node_names_.clear();

  int32 num_lines_initial = lines.size();

  ReadConfigFile(config_is, &lines);
  // now "lines" will have comments removed and empty lines stripped out

  std::vector<std::string> first_tokens(lines.size());
  std::vector<ConfigLine> config_lines(lines.size());
  for (size_t i = 0; i < lines.size(); i++) {
    std::istringstream is(lines[i]);
    std::string first_token;
    is >> first_token;
    first_tokens[i] = first_token;
    std::string rest_of_line;
    getline(is, rest_of_line);
    if (!config_lines[i].ParseLine(rest_of_line))
      KALDI_ERR << "Could not parse config-file line '" << lines[i] << "'";

  }

  // the next line will possibly remove some elements from "first_tokens" and
  // "config_lines" so nothing is doubly defined.
  RemoveRedundantConfigLines(num_lines_initial, &first_tokens, &config_lines);

  int32 initial_num_components = components_.size();
  for (int32 pass = 0; pass <= 1; pass++) {
    for (size_t i = 0; i < config_lines.size(); i++) {
      if (first_tokens[i] == "component") {
        if (pass == 0)
          ProcessComponentConfigLine(initial_num_components,
                                     &(config_lines[i]));
      } else if (first_tokens[i] == "component-node") {
        ProcessComponentNodeConfigLine(pass,  &(config_lines[i]));
      } else if (first_tokens[i] == "input-node") {
        if (pass == 0)
          ProcessInputNodeConfigLine(&(config_lines[i]));
      } else if (first_tokens[i] == "output-node") {
        ProcessOutputNodeConfigLine(pass, &(config_lines[i]));
      } else if (first_tokens[i] == "dim-range-node") {
        ProcessDimRangeNodeConfigLine(pass, &(config_lines[i]));
      } else {
        KALDI_ERR << "Invalid config-file line ('" << first_tokens[i]
                  << "' not expected): " << config_lines[i].WholeLine();
      }
    }
  }
  Check();
}

// called only on pass 0 of ReadConfig.
void Nnet::ProcessComponentConfigLine(
    int32 initial_num_components,
    ConfigLine *config) {
  std::string name, type;
  if (!config->GetValue("name", &name))
    KALDI_ERR << "Expected field name=<component-name> in config line: "
              << config->WholeLine();
  if (!IsToken(name)) // e.g. contains a space.
    KALDI_ERR << "Component name '" << name << "' is not allowed, in line: "
              << config->WholeLine();
  if (!config->GetValue("type", &type))
    KALDI_ERR << "Expected field type=<component-type> in config line: "
              << config->WholeLine();
  Component *new_component = Component::NewComponentOfType(type);
  if (new_component == NULL)
    KALDI_ERR << "Unknown component-type '" << type
              << "' in config file.  Check your code version and config.";
  // the next call will call KALDI_ERR or KALDI_ASSERT and die if something
  // went wrong.
  new_component->InitFromConfig(config);
  int32 index = GetComponentIndex(name);
  if (index != -1) {  // Replacing existing component.
    if (index >= initial_num_components) {
      // that index was something we added from this config.
      KALDI_ERR << "You are adding two components with the same name: '"
                << name << "'";
    }
    delete components_[index];
    components_[index] = new_component;
  } else {
    components_.push_back(new_component);
    component_names_.push_back(name);
  }
  if (config->HasUnusedValues())
    KALDI_ERR << "Unused values '" << config->UnusedValues()
              << " in config line: " << config->WholeLine();
}


void Nnet::ProcessComponentNodeConfigLine(
    int32 pass,
    ConfigLine *config) {

  std::string name;
  if (!config->GetValue("name", &name))
    KALDI_ERR << "Expected field name=<component-name> in config line: "
              << config->WholeLine();

  std::string input_name = name + std::string("_input");
  int32 input_node_index = GetNodeIndex(input_name),
      node_index = GetNodeIndex(name);

  if (pass == 0) {
    KALDI_ASSERT(input_node_index == -1 && node_index == -1);
    // just set up the node types and names for now, we'll properly set them up
    // on pass 1.
    nodes_.push_back(NetworkNode(kDescriptor));
    nodes_.push_back(NetworkNode(kComponent));
    node_names_.push_back(input_name);
    node_names_.push_back(name);
    return;
  } else {
    KALDI_ASSERT(input_node_index != -1 && node_index == input_node_index + 1);
    std::string component_name, input_descriptor;
    if (!config->GetValue("component", &component_name))
      KALDI_ERR << "Expected component=<component-name>, in config line: "
                << config->WholeLine();
    int32 component_index = GetComponentIndex(component_name);
    if (component_index == -1)
      KALDI_ERR << "No component named '" << component_name
                << "', in config line: " << config->WholeLine();
    nodes_[node_index].u.component_index = component_index;

    if (!config->GetValue("input", &input_descriptor))
      KALDI_ERR << "Expected input=<input-descriptor>, in config line: "
                << config->WholeLine();
    std::vector<std::string> tokens;
    if (!DescriptorTokenize(input_descriptor, &tokens))
      KALDI_ERR << "Error tokenizing descriptor in config line "
                << config->WholeLine();
    std::vector<std::string> node_names_temp;
    GetSomeNodeNames(&node_names_temp);
    tokens.push_back("end of input");
    const std::string *next_token = &(tokens[0]);
    if (!nodes_[input_node_index].descriptor.Parse(node_names_temp,
                                                   &next_token))
      KALDI_ERR << "Error parsing Descriptor in config line: "
                << config->WholeLine();
    if (config->HasUnusedValues())
      KALDI_ERR << "Unused values '" << config->UnusedValues()
                << " in config line: " << config->WholeLine();
  }
}

// called only on pass 0 of ReadConfig.
void Nnet::ProcessInputNodeConfigLine(
    ConfigLine *config) {
  std::string name;
  if (!config->GetValue("name", &name))
    KALDI_ERR << "Expected field name=<input-name> in config line: "
              << config->WholeLine();
  int32 dim;
  if (!config->GetValue("dim", &dim))
    KALDI_ERR << "Expected field dim=<input-dim> in config line: "
              << config->WholeLine();

  if (config->HasUnusedValues())
    KALDI_ERR << "Unused values '" << config->UnusedValues()
              << " in config line: " << config->WholeLine();

  KALDI_ASSERT(GetNodeIndex(name) == -1);
  if (dim <= 0)
    KALDI_ERR << "Invalid dimension in config line: " << config->WholeLine();

  int32 node_index = nodes_.size();
  nodes_.push_back(NetworkNode(kInput));
  nodes_[node_index].dim = dim;
  node_names_.push_back(name);
}


void Nnet::ProcessOutputNodeConfigLine(
    int32 pass,
    ConfigLine *config) {
  std::string name;
  if (!config->GetValue("name", &name))
    KALDI_ERR << "Expected field name=<input-name> in config line: "
              << config->WholeLine();
  int32 node_index = GetNodeIndex(name);
  if (pass == 0) {
    KALDI_ASSERT(node_index == -1);
    nodes_.push_back(NetworkNode(kDescriptor));
    node_names_.push_back(name);
  } else {
    KALDI_ASSERT(node_index != -1);
    std::string input_descriptor;
    if (!config->GetValue("input", &input_descriptor))
      KALDI_ERR << "Expected input=<input-descriptor>, in config line: "
                << config->WholeLine();
    std::vector<std::string> tokens;
    if (!DescriptorTokenize(input_descriptor, &tokens))
      KALDI_ERR << "Error tokenizing descriptor in config line "
                << config->WholeLine();
    tokens.push_back("end of input");
    // if the following fails it will die.
    std::vector<std::string> node_names_temp;
    GetSomeNodeNames(&node_names_temp);
    const std::string *next_token = &(tokens[0]);
    if (!nodes_[node_index].descriptor.Parse(node_names_temp, &next_token))
      KALDI_ERR << "Error parsing descriptor (input=...) in config line "
                << config->WholeLine();
    std::string objective_type;
    if (config->GetValue("objective", &objective_type)) {
      if (objective_type == "linear") {
        nodes_[node_index].u.objective_type = kLinear;
      } else if (objective_type == "quadratic") {
        nodes_[node_index].u.objective_type = kQuadratic;
      } else {
        KALDI_ERR << "Invalid objective type: " << objective_type;
      }
    } else {
      // the default objective type is linear.  This is what we use
      // for softmax objectives; the LogSoftmaxLayer is included as the
      // last layer, in this case.
      nodes_[node_index].u.objective_type = kLinear;
    }
    if (config->HasUnusedValues())
      KALDI_ERR << "Unused values '" << config->UnusedValues()
                << " in config line: " << config->WholeLine();
  }
}


void Nnet::ProcessDimRangeNodeConfigLine(
    int32 pass,
    ConfigLine *config) {
  std::string name;
  if (!config->GetValue("name", &name))
    KALDI_ERR << "Expected field name=<input-name> in config line: "
              << config->WholeLine();
  int32 node_index = GetNodeIndex(name);
  if (pass == 0) {
    KALDI_ASSERT(node_index == -1);
    nodes_.push_back(NetworkNode(kDimRange));
    node_names_.push_back(name);
  } else {
    KALDI_ASSERT(node_index != -1);
    std::string input_node_name;
    if (!config->GetValue("input-node", &input_node_name))
      KALDI_ERR << "Expected input-node=<input-node-name>, in config line: "
                << config->WholeLine();
    int32 dim, dim_offset;
    if (!config->GetValue("dim", &dim))
      KALDI_ERR << "Expected dim=<feature-dim>, in config line: "
                << config->WholeLine();
    if (!config->GetValue("dim-offset", &dim_offset))
      KALDI_ERR << "Expected dim-offset=<dimension-offset>, in config line: "
                << config->WholeLine();

    int32 input_node_index = GetNodeIndex(input_node_name);
    if (input_node_index == -1 ||
        !(nodes_[input_node_index].node_type == kComponent ||
          nodes_[input_node_index].node_type == kInput))
      KALDI_ERR << "invalid input-node " << input_node_name
                << ": " << config->WholeLine();

    if (config->HasUnusedValues())
      KALDI_ERR << "Unused values '" << config->UnusedValues()
                << " in config line: " << config->WholeLine();

    NetworkNode &node = nodes_[node_index];
    KALDI_ASSERT(node.node_type == kDimRange);
    node.u.node_index = input_node_index;
    node.dim = dim;
    node.dim_offset = dim_offset;
  }
}


int32 Nnet::GetNodeIndex(const std::string &node_name) const {
  size_t size = node_names_.size();
  for (size_t i = 0; i < size; i++)
    if (node_names_[i] == node_name)
      return static_cast<int32>(i);
  return -1;
}

int32 Nnet::GetComponentIndex(const std::string &component_name) const {
  size_t size = component_names_.size();
  for (size_t i = 0; i < size; i++)
    if (component_names_[i] == component_name)
      return static_cast<int32>(i);
  return -1;
}


// note: the input to this function is a config generated from the nnet,
// containing the node info, concatenated with a config provided by the user.
//static
void Nnet::RemoveRedundantConfigLines(int32 num_lines_initial,
                                      std::vector<std::string> *first_tokens,
                                      std::vector<ConfigLine> *configs) {
  int32 num_lines = first_tokens->size();
  KALDI_ASSERT(configs->size() == num_lines &&
               num_lines_initial <= num_lines);
  // node names and component names live in different namespaces.
  unordered_map<std::string, int32, StringHasher> node_name_to_most_recent_line;
  unordered_set<std::string, StringHasher> component_names;
  typedef unordered_map<std::string, int32, StringHasher>::iterator IterType;

  std::vector<bool> to_remove(num_lines, false);
  for (int32 line = 0; line < num_lines; line++) {
    std::string first_token = (*first_tokens)[line];
    ConfigLine &config_line = (*configs)[line];
    std::string name;
    if (!config_line.GetValue("name", &name))
      KALDI_ERR << "Config line has no field 'name=xxx': "
                << config_line.WholeLine();
    if (!IsValidName(name))
      KALDI_ERR << "Name '" << name << "' is not allowable, in line: "
                << config_line.WholeLine();
    if ((*first_tokens)[line] == "component") {
      // a line starting with "component"... components live in their own
      // namespace.  No repeats are allowed because we never wrote them
      // to the config generated from the nnet.
      if (!component_names.insert(name).second) {
        // we could not insert it because it was already there.
        KALDI_ERR << "Component name " << name
                  << " appears twice in the same config file.";
      }
    } else {
      // the line defines some sort of network node, e.g. component-node.
      IterType iter = node_name_to_most_recent_line.find(name);
      if (iter != node_name_to_most_recent_line.end()) {
        // name is repeated.
        int32 prev_line = iter->second;
        if (prev_line >= num_lines_initial) {
          // user-provided config contained repeat of node with this name.
          KALDI_ERR << "Node name " << name
                    << " appears twice in the same config file.";
        }
        // following assert checks that the config-file generated
        // from an actual nnet does not contain repeats.. that
        // would be a bug so check it with assert.
        KALDI_ASSERT(line >= num_lines_initial);
        to_remove[prev_line] = true;
      }
      node_name_to_most_recent_line[name] = line;
    }
  }
  // Now remove any lines with to_remove[i] = true.
  std::vector<std::string> first_tokens_out;
  std::vector<ConfigLine> configs_out;
  first_tokens_out.reserve(num_lines);
  configs_out.reserve(num_lines);
  for (int32 i = 0; i < num_lines; i++) {
    if (!to_remove[i]) {
      first_tokens_out.push_back((*first_tokens)[i]);
      configs_out.push_back((*configs)[i]);
    }
  }
  first_tokens->swap(first_tokens_out);
  configs->swap(configs_out);
}

// copy constructor.
NetworkNode::NetworkNode(const NetworkNode &other):
    node_type(other.node_type),
    descriptor(other.descriptor),
    dim(other.dim),
    dim_offset(other.dim_offset) {
  u.component_index = other.u.component_index;
}


void Nnet::Destroy() {
  for (size_t i = 0; i < components_.size(); i++)
    delete components_[i];
  component_names_.clear();
  components_.clear();
  node_names_.clear();
  nodes_.clear();
}

void Nnet::GetSomeNodeNames(
    std::vector<std::string> *modified_node_names) const {
  modified_node_names->resize(node_names_.size());
  const std::string invalid_name = "**";
  size_t size = node_names_.size();
  for (size_t i = 0; i < size; i++) {
    if (nodes_[i].node_type == kComponent ||
        nodes_[i].node_type == kInput ||
        nodes_[i].node_type == kDimRange) {
      (*modified_node_names)[i] = node_names_[i];
    } else {
      (*modified_node_names)[i] = invalid_name;
    }
  }
}

void Nnet::Read(std::istream &is, bool binary) {
  Destroy();
  ExpectToken(is, binary, "<Nnet3>");
  std::ostringstream config_file_out;
  std::string cur_line;
  getline(is, cur_line);  // Eat up a single newline.
  if (!(cur_line == "" || cur_line == "\r"))
    KALDI_ERR << "Expected newline in config file, got " << cur_line;
  while (getline(is, cur_line)) {
    // config-file part of file is terminated by an empty line.
    if (cur_line == "" || cur_line == "\r")
      break;
    config_file_out << cur_line << std::endl;
  }
  // Now we read the Components; later we try to parse the config_lines.
  ExpectToken(is, binary, "<NumComponents>");
  int32 num_components;
  ReadBasicType(is, binary, &num_components);
  KALDI_ASSERT(num_components >= 0 && num_components < 100000);
  components_.resize(num_components, NULL);
  component_names_.resize(num_components);
  for (int32 c = 0; c < num_components; c++) {
    ExpectToken(is, binary, "<ComponentName>");
    ReadToken(is, binary, &(component_names_[c]));
    components_[c] = Component::ReadNew(is, binary);
  }
  ExpectToken(is, binary, "</Nnet3>");
  std::istringstream config_file_in(config_file_out.str());
  this->ReadConfig(config_file_in);
}

void Nnet::Write(std::ostream &os, bool binary) const {
  WriteToken(os, binary, "<Nnet3>");
  os << std::endl;
  std::vector<std::string> config_lines;
  const bool include_dim = false;
  GetConfigLines(include_dim, &config_lines);
  for (size_t i = 0; i < config_lines.size(); i++) {
    KALDI_ASSERT(!config_lines[i].empty());
    os << config_lines[i] << std::endl;
  }
  // A blank line terminates the config-like section of the file.
  os << std::endl;
  // Now write the Components
  int32 num_components = components_.size();
  WriteToken(os, binary, "<NumComponents>");
  WriteBasicType(os, binary, num_components);
  if (!binary)
    os << std::endl;
  for (int32 c = 0; c < num_components; c++) {
    WriteToken(os, binary, "<ComponentName>");
    WriteToken(os, binary, component_names_[c]);
    components_[c]->Write(os, binary);
    if (!binary)
      os << std::endl;
  }
  WriteToken(os, binary, "</Nnet3>");
}

int32 Nnet::Modulus() const {
  int32 ans = 1;
  for (int32 n = 0; n < NumNodes(); n++) {
    const NetworkNode &node = nodes_[n];
    if (node.node_type == kDescriptor)
      ans = Lcm(ans, node.descriptor.Modulus());
  }
  return ans;
}


int32 Nnet::InputDim(const std::string &input_name) const {
  int32 n = GetNodeIndex(input_name);
  if (n == -1) return -1;
  const NetworkNode &node = nodes_[n];
  if (node.node_type != kInput) return -1;
  return node.dim;
}

int32 Nnet::OutputDim(const std::string &input_name) const {
  int32 n = GetNodeIndex(input_name);
  if (n == -1 || !IsOutputNode(n)) return -1;
  const NetworkNode &node = nodes_[n];
  return node.Dim(*this);
}

const std::string& Nnet::GetNodeName(int32 node_index) const {
  KALDI_ASSERT(static_cast<size_t>(node_index) < node_names_.size());
  return node_names_[node_index];
}

const std::string& Nnet::GetComponentName(int32 component_index) const {
  KALDI_ASSERT(static_cast<size_t>(component_index) < component_names_.size());
  return component_names_[component_index];
}

void Nnet::Check() const {
  int32 num_nodes = nodes_.size(),
    num_input_nodes = 0,
    num_output_nodes = 0;
  KALDI_ASSERT(num_nodes != 0);
  std::vector<bool> component_used(components_.size());
  for (int32 n = 0; n < num_nodes; n++) {
    const NetworkNode &node = nodes_[n];
    std::string node_name = node_names_[n];
    KALDI_ASSERT(GetNodeIndex(node_name) == n);
    switch (node.node_type) {
      case kInput:
        KALDI_ASSERT(node.dim > 0);
        num_input_nodes++;
        break;
      case kDescriptor: {
        if (IsOutputNode(n))
          num_output_nodes++;
        std::vector<int32> node_deps;
        node.descriptor.GetNodeDependencies(&node_deps);
        SortAndUniq(&node_deps);
        for (size_t i = 0; i < node_deps.size(); i++) {
          int32 src_node = node_deps[i];
          KALDI_ASSERT(src_node >= 0 && src_node < num_nodes);
          NodeType src_type = nodes_[src_node].node_type;
          if (src_type != kInput && src_type != kDimRange &&
              src_type != kComponent)
            KALDI_ERR << "Invalid source node type in Descriptor: source node "
                      << node_names_[src_node];
        }
        break;
      }
      case kComponent: {
        KALDI_ASSERT(n > 0 && nodes_[n-1].node_type == kDescriptor);
        const NetworkNode &src_node = nodes_[n-1];
        const Component *c = GetComponent(node.u.component_index);
        component_used[node.u.component_index] = true;
        int32 src_dim = src_node.Dim(*this), input_dim = c->InputDim();
        if (src_dim != input_dim) {
          KALDI_ERR << "Dimension mismatch for network-node "
                    << node_name << ": input-dim "
                    << src_dim << " versus component-input-dim "
                    << input_dim;
        }
        break;
      }
      case kDimRange: {
        int32 input_node = node.u.node_index;
        KALDI_ASSERT(input_node >= 0 && input_node < num_nodes);
        NodeType input_type = nodes_[input_node].node_type;
        if (input_type != kInput && input_type != kComponent)
          KALDI_ERR << "Invalid source node type in DimRange node: source node "
                    << node_names_[input_node];
        int32 input_dim = nodes_[input_node].Dim(*this);
        if (!(node.dim > 0 && node.dim_offset >= 0 &&
              node.dim + node.dim_offset <= input_dim)) {
          KALDI_ERR << "Invalid node dimensions for DimRange node: " << node_name
                    << ": input-dim=" << input_dim << ", dim=" << node.dim
                    << ", dim-offset=" << node.dim_offset;
        }
        break;
      }
      default:
        KALDI_ERR << "Invalid node type for node " << node_name;
    }
  }

  int32 num_components = components_.size();
  for (int32 c = 0; c < num_components; c++) {
    const std::string &component_name = component_names_[c];
    if (!component_used[c]) {
      KALDI_WARN << "Orphan component " << component_name;
    }
    KALDI_ASSERT(GetComponentIndex(component_name) == c &&
                 "Duplicate component names?");
  }
  KALDI_ASSERT(num_input_nodes > 0);
  KALDI_ASSERT(num_output_nodes > 0);
}

struct NerualStatsInfo {
  int32 idx_before;
  int32 idx_after;
  Vector<BaseFloat> ionorms;
  explicit NerualStatsInfo(int32 before, int32 after,
    const Vector<BaseFloat> norms):
    idx_before(before), idx_after(after),
    ionorms(norms) { }
  std::string Info() {
    std::ostringstream os;
    os << "affine before idx is " << idx_before;
    os << ", affine after idx is " << idx_after;
    // os << ", ionorms is " << ionorms;
    return os.str();
  }
};

// only TDNN now
void Nnet::Prune(const NnetNeuralPruneOpts &prune_opts) {
  int32 num_nodes = nodes_.size(),
    num_input_nodes = 0,
    num_output_nodes = 0;
  KALDI_ASSERT(num_nodes != 0);
  std::vector<bool> component_used(components_.size());

  {
    int32 neural_num = 0;
    std::vector<struct NerualStatsInfo> neural_stats_info;
    std::vector<std::vector<int32> > neural_prune_idxs;

    for (int32 stage = 0; stage < 2; stage++) {
      int32 affine_before_idx = -1;
      AffineComponent *affine_before = NULL;
      AffineComponent *affine_after = NULL;
      std::vector<int32> between_components;
      int32 i = 0;
      // ComputeStatsInfo(); / DoPruning();
      for (int32 n = 0; n < num_nodes; n++) {
        const NetworkNode &node = nodes_[n];
        std::string node_name = node_names_[n];
        KALDI_ASSERT(GetNodeIndex(node_name) == n);
        switch (node.node_type) {
          case kInput:
            KALDI_ASSERT(node.dim > 0);
            num_input_nodes++;
            break;
          case kDescriptor: {
            if (IsOutputNode(n))
              num_output_nodes++;
            std::vector<int32> node_deps;
            node.descriptor.GetNodeDependencies(&node_deps);
            SortAndUniq(&node_deps);
            for (size_t i = 0; i < node_deps.size(); i++) {
              int32 src_node = node_deps[i];
              KALDI_ASSERT(src_node >= 0 && src_node < num_nodes);
              NodeType src_type = nodes_[src_node].node_type;
              if (src_type != kInput && src_type != kDimRange &&
                  src_type != kComponent)
                KALDI_ERR << "Invalid source node type in Descriptor: source node "
                          << node_names_[src_node];
            }
            break;
          }
          case kComponent: {
            KALDI_ASSERT(n > 0 && nodes_[n-1].node_type == kDescriptor);
            const NetworkNode &src_node = nodes_[n-1];
            Component *c = GetComponent(node.u.component_index);
            KALDI_LOG << "Component Info: " << c->Info();
            component_used[node.u.component_index] = true;
            int32 src_dim = src_node.Dim(*this), input_dim = c->InputDim();
            if (src_dim != input_dim) {
              KALDI_ERR << "Dimension mismatch for network-node "
                        << node_name << ": input-dim "
                        << src_dim << " versus component-input-dim "
                        << input_dim;
            }
            AffineComponent *affine = dynamic_cast<AffineComponent*>(c);
            if (affine != NULL) {
              if (affine_before == NULL) {
                affine_before = affine;
                between_components.clear();
              } else {
                if (affine_after != NULL)
                  affine_before = affine_after;
                affine_after = affine;

                switch (stage) {
                  case 0: {
                    neural_num += affine_before->OutputDim();
                    Vector<BaseFloat> vec(affine_before->OutputDim());
                    Matrix<BaseFloat>  W_before(affine_before->LinearParams());
                    W_before.ApplyPowAbs(1.0, false); // abs
                    vec.AddColSumMat((1.0 - prune_opts.lambda) / W_before.NumCols(), W_before, 0.0);

                    Matrix<BaseFloat>  W_after(affine_after->LinearParams());
                    W_after.ApplyPowAbs(1.0, false); // abs
                    KALDI_ASSERT(W_after.NumCols() % W_before.NumRows() == 0);
                    for (int32 offset = 0; offset < W_after.NumCols(); offset += W_before.NumRows()) {
                      vec.AddRowSumMat(prune_opts.lambda / W_after.NumRows(), W_after.ColRange(offset, W_before.NumRows()), 1.0); //SumRows
                    }
                    // store affine before after index
                    neural_stats_info.push_back(NerualStatsInfo(affine_before_idx, node.u.component_index, vec));
                    break;
                  }
                  case 1: {
                    KALDI_LOG << "=========== Pruning... i=" << i << ", affine_before_idx=" << affine_before_idx << ", stat.info="
                      << neural_stats_info[i].Info();
                    const NerualStatsInfo &stat = neural_stats_info[i];
                    const std::vector<int32> &cut_idx = neural_prune_idxs[i];
                    int32 num_cut = cut_idx.size();

                    KALDI_ASSERT(affine_before_idx == stat.idx_before);
                    KALDI_ASSERT(node.u.component_index == stat.idx_after);

                    //
                    AffineComponent* affine_com_before = dynamic_cast<AffineComponent*>(GetComponent(stat.idx_before));
                    AffineComponent* affine_com_after = dynamic_cast<AffineComponent*>(GetComponent(stat.idx_after));
                    if (affine_com_before == NULL || affine_com_after == NULL)
                        KALDI_ERR << "Error stats info.";
                    // step 1 修改 NonlinearComponents(c)  的维数
                    for (int32 k = 0; k < between_components.size(); k++) {
                      int32 cindex = between_components[k];
                      NonlinearComponent* nonlinear_com = dynamic_cast<NonlinearComponent*>(GetComponent(cindex));
                      KALDI_LOG << "Component Info: " << GetComponent(cindex)->Info();

                      if (nonlinear_com != NULL) {
                        int32 dim = nonlinear_com->InputDim();  // InputDim() == OutputDim()
                        KALDI_ASSERT(nonlinear_com->InputDim() == nonlinear_com->OutputDim());
                        if (dim - num_cut <= 0) {
                          KALDI_LOG << "WARNING: cut too many neural nodes at Component: " << cindex << ", maybe you should set percent or threshold smaller.";
                          continue;
                        }
                        nonlinear_com->SetDim(dim - num_cut);
                        // 
                        Vector<double> value_sum_cpu(nonlinear_com->ValueSum());
                        Vector<double> deriv_sum_cpu(nonlinear_com->DerivSum());
                        for (int32 j = 0; j < cut_idx.size(); ++j) {
                          int32 idx = cut_idx[j];
                          value_sum_cpu.RemoveElement(idx - j);
                          deriv_sum_cpu.RemoveElement(idx - j);
                        }
                        CuVector<double> &value_sum = const_cast<CuVector<double> &>(nonlinear_com->ValueSum());
                        CuVector<double> &deriv_sum = const_cast<CuVector<double> &>(nonlinear_com->DerivSum());
                        value_sum = value_sum_cpu;
                        deriv_sum = deriv_sum_cpu;
                      } else if (GetComponent(cindex)->Type() == "NormalizeComponent") {
                        NormalizeComponent *comp = dynamic_cast<NormalizeComponent*>(GetComponent(cindex));
                        comp->SetDim(comp->InputDim() - num_cut);
                      } else if (GetComponent(cindex)->Type() == "BatchNormalizeComponent") {
                        // NormalizeComponent *comp = dynamic_cast<NormalizeComponent*>(GetComponent(cindex));
                        // comp->SetDim(comp->InputDim() - num_cut);
                        KALDI_ERR << "TODO";
                      } else {
                        KALDI_WARN << "Not NonlinearComponent/NormalizeComponent: " << GetComponent(cindex)->Info();
                      }
                    }

                    // step2 修改 c-1 c+1 AffineTransform的 W bias
                    Vector<BaseFloat> bias_params_before(affine_com_before->BiasParams());
                    Matrix<BaseFloat> linear_params_before(affine_com_before->LinearParams());

                    const Vector<BaseFloat> bias_params_after(affine_com_after->BiasParams());
                    Matrix<BaseFloat> linear_params_after(affine_com_after->LinearParams());
                    int32 offset = linear_params_before.NumRows();

                    for (int32 j = 0; j < cut_idx.size(); ++j) {
                      int32 idx = cut_idx[j];
                      bias_params_before.RemoveElement(idx - j);
                      linear_params_before.RemoveRow(idx - j);
                    }

                    linear_params_after.Transpose(); // 因为Matrix类没有 RemoveCol()方法，这里做个转置，RemoveRow()
                    int32 num_cols = linear_params_after.NumRows();
                    for (int32 k = 0; k < num_cols / offset; k += 1) {
                      for (int32 j = 0; j < cut_idx.size(); ++j) {
                        int32 idx = cut_idx[j] + k * (offset - cut_idx.size());
                        linear_params_after.RemoveRow(idx - j);
                      }
                    }
                    affine_com_before->SetParams(bias_params_before, linear_params_before);
                    linear_params_after.Transpose(); // 转置回来
                    affine_com_after->SetParams(bias_params_after, linear_params_after);
                    break;
                  }
                }
                i++;
                between_components.clear();
              }
              affine_before_idx = node.u.component_index;
            } else {
              between_components.push_back(node.u.component_index);
            }
            break;
          }
          case kDimRange: {
            int32 input_node = node.u.node_index;
            KALDI_ASSERT(input_node >= 0 && input_node < num_nodes);
            NodeType input_type = nodes_[input_node].node_type;
            if (input_type != kInput && input_type != kComponent)
              KALDI_ERR << "Invalid source node type in DimRange node: source node "
                        << node_names_[input_node];
            int32 input_dim = nodes_[input_node].Dim(*this);
            if (!(node.dim > 0 && node.dim_offset >= 0 &&
                  node.dim + node.dim_offset <= input_dim)) {
              KALDI_ERR << "Invalid node dimensions for DimRange node: " << node_name
                        << ": input-dim=" << input_dim << ", dim=" << node.dim
                        << ", dim-offset=" << node.dim_offset;
            }
            break;
          }
          default:
            KALDI_ERR << "Invalid node type for node " << node_name;
        }
      }

      // LabelToPrunedNodes();
      BaseFloat thres = 0;
      for (int32 i = 0; i < neural_stats_info.size(); ++i) {
        KALDI_LOG << i << "-th ionorms " << neural_stats_info[i].ionorms;
      }
      if (!prune_opts.per_layer) {
        if (prune_opts.percent >= 0) {
          std::vector<BaseFloat> all_value;
          for (int32 i = 0; i < neural_stats_info.size(); ++i) {
            BaseFloat* value = neural_stats_info[i].ionorms.Data();
            BaseFloat  len = neural_stats_info[i].ionorms.Dim();
            for (int32 j = 0; j < len; ++j) {
                all_value.push_back(value[j]);
            }
          }
          int32 idx = neural_num * prune_opts.percent;
          std::nth_element(all_value.begin(), all_value.begin() + idx, all_value.end());
          thres = *(all_value.begin() + idx);
        }

        KALDI_ASSERT(thres >= 0);

        for (int32 i = 0; i < neural_stats_info.size(); ++i) {
          neural_prune_idxs.push_back(std::vector<int32>());
          BaseFloat* value = neural_stats_info[i].ionorms.Data();
          int32  len = neural_stats_info[i].ionorms.Dim();
          // 为防止减去过多node，这里做一个限制，最多减去80%=4/5
          // sort *value
          std::sort(value, value + len - 1);
          BaseFloat thres_cut = std::min(thres, value[len * 4 / 5]);
          for (int32 j = 0; j < len; ++j) {
            if (value[j] < thres_cut) {
              neural_prune_idxs[i].push_back(j);
            }
          }
        }
      } else { // per_layer == true
        for (int32 i = 0; i < neural_stats_info.size(); ++i) {
          if (prune_opts.percent >= 0) {
            int32 dim = neural_stats_info[i].ionorms.Dim();
            int32 idx = dim * prune_opts.percent;
            std::nth_element(neural_stats_info[i].ionorms.Data(), neural_stats_info[i].ionorms.Data() + idx, neural_stats_info[i].ionorms.Data() + dim);
            thres = *(neural_stats_info[i].ionorms.Data() + idx);
          }
          KALDI_ASSERT(thres >= 0);

          neural_prune_idxs.push_back(std::vector<int32>());
          BaseFloat* value = neural_stats_info[i].ionorms.Data();
          int32  len = neural_stats_info[i].ionorms.Dim();
          // 为防止减去过多node，这里做一个限制，最多减去80%=4/5
          // sort *value
          std::sort(value, value + len - 1);
          BaseFloat thres_cut = std::min(thres, value[len * 4 / 5]);
          for (int32 j = 0; j < len; ++j) {
            if (value[j] < thres_cut) {
              neural_prune_idxs[i].push_back(j);
            }
          }
        }
      }
    }
  }

  Check();
}


// copy constructor
Nnet::Nnet(const Nnet &nnet):
    component_names_(nnet.component_names_),
    components_(nnet.components_.size()),
    node_names_(nnet.node_names_),
    nodes_(nnet.nodes_) {
  for (size_t i = 0; i < components_.size(); i++)
    components_[i] = nnet.components_[i]->Copy();
  Check();
}

Nnet& Nnet::operator =(const Nnet &nnet) {
  if (this == &nnet)
    return *this;
  Destroy();
  component_names_ = nnet.component_names_;
  components_.resize(nnet.components_.size());
  node_names_ = nnet.node_names_;
  nodes_ = nnet.nodes_;
  for (size_t i = 0; i < components_.size(); i++)
    components_[i] = nnet.components_[i]->Copy();
  Check();
  return *this;
}

std::string Nnet::Info() const {
  std::ostringstream os;
  os << "num-parameters: " << NumParameters(*this) << "\n";
  os << "modulus: " << this->Modulus() << "\n";
  std::vector<std::string> config_lines;
  bool include_dim = true;
  GetConfigLines(include_dim, &config_lines);
  for (size_t i = 0; i < config_lines.size(); i++)
    os << config_lines[i] << "\n";
  // Get component info.
  for (size_t i = 0; i < components_.size(); i++)
    os << "component name=" << component_names_[i]
       << " type=" << components_[i]->Info() << "\n";
  return os.str();
}

} // namespace nnet3
} // namespace kaldi
